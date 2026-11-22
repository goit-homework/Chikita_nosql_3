// queries/part5_gds.cypher (додаткова частина)
// Запуск: cat queries/part5_gds.cypher | docker exec -i neo4j_movielens cypher-shell -u neo4j -p password123 --format verbose
// Neo4j 5.18.1, GDS 2.6.9. id() у Neo4j 5 застаріла, тому пари впорядковуємо через elementId().

// Якщо попередній запуск обірвався: прибираємо проєкції і тимчасові ребра
CALL gds.graph.drop('movieGraph', false) YIELD graphName RETURN graphName;
CALL gds.graph.drop('userSimilarity', false) YIELD graphName RETURN graphName;
CALL gds.graph.drop('userGraph', false) YIELD graphName RETURN graphName;
CALL gds.graph.drop('likes', false) YIELD graphName RETURN graphName;
CALL gds.graph.drop('userJaccard', false) YIELD graphName RETURN graphName;
CALL gds.graph.drop('noHub', false) YIELD graphName RETURN graphName;
MATCH ()-[s:SIMILAR_JACCARD]->() DELETE s;
MATCH ()-[co:CO_RATED]-() DELETE co;
MATCH ()-[sim:SIMILAR]-() DELETE sim;

// ============================================================
// 5.1. PageRank на графі фільмів
// ============================================================

// Крок 1: ребра фільм-фільм через спільних користувачів (обидва фільми оцінені на 4-5).
// Одна зміна проти коду з умови: умову "понад 20 оцінок" рахуємо через COUNT { } до агрегації.
// У варіанті з умови size([(m1)<-[:RATED]-() | 1]) після агрегації будує список із тисяч ребер
// для кожної з мільйонів пар фільмів, і контейнер з heap 2G за 72 с вбив OOM-кілер.
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND elementId(m1) < elementId(m2)
  AND COUNT { (m1)<-[:RATED]-() } > 20 AND COUNT { (m2)<-[:RATED]-() } > 20
WITH m1, m2, count(u) AS weight
ORDER BY weight DESC, m1.movieId, m2.movieId
LIMIT 50000
MERGE (m1)-[co:CO_RATED]-(m2)
SET co.weight = weight;

MATCH (m:Movie)-[co:CO_RATED]-()
RETURN count(DISTINCT m) AS movies_with_co_rated, count(co) / 2 AS co_rated_edges,
       min(co.weight) AS min_weight, max(co.weight) AS max_weight;

// Крок 2: проєкція в пам'яті GDS
CALL gds.graph.project(
  'movieGraph',
  'Movie',
  { CO_RATED: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: PageRank з вагою ребер; спершу перевіряємо збіжність
// 50 ітерацій не вистачало (didConverge = false); зі 100 PageRank сходиться за 88
CALL gds.pageRank.stats('movieGraph', { relationshipWeightProperty: 'weight', maxIterations: 100 })
YIELD didConverge, ranIterations;

CALL gds.pageRank.write('movieGraph', {
  relationshipWeightProperty: 'weight', maxIterations: 100, writeProperty: 'pagerank'
})
YIELD nodePropertiesWritten, didConverge;

// Топ-15 за PageRank поруч із популярністю: усі оцінки, оцінки 4-5 і середня оцінка
MATCH (m:Movie)
WHERE COUNT { (m)-[:CO_RATED]-() } > 0
CALL { WITH m MATCH (m)<-[r:RATED]-() RETURN count(r) AS ratings, avg(r.rating) AS avg_rating }
WITH m, ratings, avg_rating,
     COUNT { (m)<-[r:RATED]-() WHERE r.rating >= 4 } AS high_ratings,
     COUNT { (m)-[:CO_RATED]-() } AS co_rated_neighbours
RETURN m.title AS title, m.year AS year, round(m.pagerank, 3) AS pagerank,
       co_rated_neighbours, ratings, high_ratings, round(avg_rating, 2) AS avg_rating
ORDER BY pagerank DESC, title
LIMIT 15;

// Наскільки PageRank пояснюється популярністю: кореляція Пірсона з кількістю оцінок
// і з кількістю оцінок 4-5 серед фільмів, що мають ребра CO_RATED
MATCH (m:Movie)
WHERE COUNT { (m)-[:CO_RATED]-() } > 0
CALL { WITH m MATCH (m)<-[r:RATED]-() RETURN toFloat(count(r)) AS ratings, avg(r.rating) AS avg_rating }
WITH m.pagerank AS pr, ratings, avg_rating,
     toFloat(COUNT { (m)<-[r:RATED]-() WHERE r.rating >= 4 }) AS high
WITH collect([pr, ratings, high, avg_rating]) AS rows, avg(pr) AS mp, avg(ratings) AS mr, avg(high) AS mh, avg(avg_rating) AS ma
UNWIND rows AS x
WITH mp, mr, mh, ma,
     sum((x[0] - mp) * (x[1] - mr)) AS c_r, sum((x[0] - mp) * (x[2] - mh)) AS c_h, sum((x[0] - mp) * (x[3] - ma)) AS c_a,
     sum((x[0] - mp) ^ 2) AS v_p, sum((x[1] - mr) ^ 2) AS v_r, sum((x[2] - mh) ^ 2) AS v_h, sum((x[3] - ma) ^ 2) AS v_a
RETURN round(c_r / sqrt(v_p * v_r), 3) AS pearson_with_ratings,
       round(c_h / sqrt(v_p * v_h), 3) AS pearson_with_high_ratings,
       round(c_a / sqrt(v_p * v_a), 3) AS pearson_with_avg_rating;

// Фільми з найбільшою кількістю оцінок, але не в топі PageRank
MATCH (m:Movie)
WHERE COUNT { (m)-[:CO_RATED]-() } > 0
WITH m ORDER BY m.pagerank DESC
WITH collect(m) AS by_pagerank
UNWIND range(0, size(by_pagerank) - 1) AS i
WITH by_pagerank[i] AS m, i + 1 AS pagerank_rank
CALL { WITH m MATCH (m)<-[r:RATED]-() RETURN count(r) AS ratings, avg(r.rating) AS avg_rating }
WITH m, pagerank_rank, ratings, avg_rating
ORDER BY ratings DESC, m.title
LIMIT 10
RETURN m.title AS title, ratings, round(avg_rating, 2) AS avg_rating, pagerank_rank;

// Крок 4: видаляємо проєкцію та тимчасові ребра
CALL gds.graph.drop('movieGraph') YIELD graphName RETURN graphName;
MATCH ()-[co:CO_RATED]-() DELETE co;

// ============================================================
// 5.2. Спільноти користувачів (Louvain)
// ============================================================

// Крок 1: ребра користувач-користувач через спільні фільми з оцінкою 4-5.
// Запит з умови агрегує 190,8 млн рядків у хеш-таблицю на мільйони пар користувачів,
// і контейнер з heap 2G вбив OOM-кілер через 21 с. Тут пари рахуються окремо для кожного
// користувача в CALL { } (не більше 6 040 записів за раз), а назовні виходять лише пари з
// weight >= 100. Таких пар 87 105, тож 50 000 найважчих з умови повністю серед них.
MATCH (u1:User)
CALL {
  WITH u1
  MATCH (u1)-[r1:RATED]->(:Movie)<-[r2:RATED]-(u2:User)
  WHERE r1.rating >= 4 AND r2.rating >= 4 AND elementId(u1) < elementId(u2)
  WITH u2, count(*) AS weight
  WHERE weight >= 100
  RETURN u2, weight
}
WITH u1, u2, weight
ORDER BY weight DESC, u1.userId, u2.userId
LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

MATCH (u:User)-[s:SIMILAR]-()
RETURN count(DISTINCT u) AS users_with_similar, count(s) / 2 AS similar_edges,
       min(s.weight) AS min_weight, max(s.weight) AS max_weight;

// Крок 2: проєкція
CALL gds.graph.project(
  'userSimilarity',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Louvain і запис номера спільноти у вузли
CALL gds.louvain.write('userSimilarity', {
  relationshipWeightProperty: 'weight', writeProperty: 'community',
  concurrency: 1   // паралельний Louvain дає різні розбиття між запусками
})
YIELD communityCount, modularity, ranLevels;

// Крок 4а: 10 найбільших спільнот серед користувачів, що мають ребра SIMILAR
// (користувачі без ребер стають окремими спільнотами з одного вузла)
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
WITH u.community AS community, count(*) AS users,
     round(100.0 * sum(CASE WHEN u.gender = 'F' THEN 1 ELSE 0 END) / count(*), 1) AS women_pct,
     round(avg(COUNT { (u)-[:RATED]->() })) AS avg_ratings_per_user
RETURN community, users, women_pct, avg_ratings_per_user
ORDER BY users DESC, community
LIMIT 10;

// Крок 4б: топ-3 жанри кожної з 10 найбільших спільнот за фільмами з оцінкою 4-5
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
WITH u.community AS community, count(*) AS users
ORDER BY users DESC, community
LIMIT 10
WITH collect(community) AS top_communities
MATCH (u:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE u.community IN top_communities AND r.rating >= 4
WITH u.community AS community, g.name AS genre, count(*) AS n
ORDER BY community, n DESC, genre
WITH community, collect(genre)[0..3] AS top3_genres, collect(n)[0..3] AS counts, sum(n) AS all_high_ratings
RETURN community, top3_genres, [c IN counts | round(100.0 * c / all_high_ratings, 1)] AS top3_share_pct
ORDER BY community;

// Крок 4в: чим спільноти відрізняються. Drama і Comedy лідирують майже скрізь, тому
// рахуємо підйом (lift): частка жанру в оцінках 4-5 спільноти / частка жанру в усіх оцінках 4-5.
MATCH (:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE r.rating >= 4
WITH g.name AS genre, count(*) AS n
WITH collect([genre, n]) AS overall, sum(n) AS total
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
WITH overall, total, u.community AS community, count(*) AS users
ORDER BY users DESC, community
LIMIT 10
WITH overall, total, collect(community) AS top_communities
MATCH (u:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE u.community IN top_communities AND r.rating >= 4
WITH overall, total, u.community AS community, g.name AS genre, count(*) AS n
WITH overall, total, community, collect([genre, n]) AS rows, sum(n) AS community_total
UNWIND rows AS row
WITH community, row[0] AS genre, row[1] AS n, community_total,
     [o IN overall WHERE o[0] = row[0]][0][1] AS overall_n, total
WHERE n >= 50
WITH community, genre, (toFloat(n) / community_total) / (toFloat(overall_n) / total) AS lift
ORDER BY community, lift DESC, genre
WITH community, collect(genre + ' x' + toString(round(lift, 2)))[0..3] AS most_distinctive
RETURN community, most_distinctive
ORDER BY community;

// Проєкцію видаляємо, ребра SIMILAR лишаємо для 5.3
CALL gds.graph.drop('userSimilarity') YIELD graphName RETURN graphName;

// ============================================================
// 5.3. Найкоротший шлях між користувачами
// ============================================================

// Ребра SIMILAR з 5.2 ще існують, тож матеріалізацію не повторюємо.
// weight - схожість (більше = ближче), а Дейкстра мінімізує суму ваг. Тому для
// "найміцнішого" ланцюжка додаємо вартість 1 / weight; без ваги Дейкстра рахує кроки.
MATCH ()-[s:SIMILAR]->()
SET s.cost = 1.0 / s.weight;

CALL gds.graph.project(
  'userGraph',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: ['weight', 'cost'] } }
)
YIELD graphName, nodeCount, relationshipCount;

// Зв'язність: скільки компонент утворюють користувачі з ребрами SIMILAR
CALL gds.wcc.stream('userGraph')
YIELD nodeId, componentId
WITH gds.util.asNode(nodeId) AS u, componentId
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
WITH componentId, count(*) AS size
RETURN count(*) AS components, max(size) AS largest_component, sum(size) AS users_in_graph;

// Кілька пар: найменш і найбільш активні користувачі графа SIMILAR, а також
// користувачі з різних спільнот. Кількість кроків - Дейкстра без ваги.
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
WITH u ORDER BY COUNT { (u)-[:SIMILAR]-() } ASC, u.userId
WITH collect(u) AS users
WITH users[0] AS a, users[1] AS b, users[2] AS c, users[size(users) - 1] AS hub
UNWIND [[a, b], [a, c], [b, c], [a, hub]] AS pair
WITH pair[0] AS source, pair[1] AS target
CALL gds.shortestPath.dijkstra.stream('userGraph', { sourceNode: source, targetNode: target })
YIELD totalCost, nodeIds
RETURN source.userId AS from_user, target.userId AS to_user, toInteger(totalCost) AS hops,
       size(nodeIds) - 2 AS intermediate_users,
       [n IN gds.util.asNodes(nodeIds) | n.userId] AS chain;

// Той самий перший шлях з вартістю 1 / weight: ланцюжок через найсхожіших користувачів
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
WITH u ORDER BY COUNT { (u)-[:SIMILAR]-() } ASC, u.userId
WITH collect(u) AS users
WITH users[0] AS source, users[1] AS target
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source, targetNode: target, relationshipWeightProperty: 'cost'
})
YIELD totalCost, nodeIds
RETURN source.userId AS from_user, target.userId AS to_user, size(nodeIds) - 1 AS hops,
       [n IN gds.util.asNodes(nodeIds) | n.userId] AS strongest_chain;

// Середня довжина шляху: відстані від 20 випадкових користувачів до всіх досяжних
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
WITH u ORDER BY u.userId
WITH collect(u) AS users
UNWIND range(0, 19) AS i
WITH users[(i * 7919) % size(users)] AS source
CALL gds.allShortestPaths.dijkstra.stream('userGraph', { sourceNode: source })
YIELD targetNode, totalCost
WHERE gds.util.asNode(targetNode) <> source
RETURN count(*) AS paths, round(avg(totalCost), 2) AS avg_hops, max(totalCost) AS max_hops,
       round(100.0 * sum(CASE WHEN totalCost <= 6 THEN 1 ELSE 0 END) / count(*), 1) AS within_6_pct;

// Хто стоїть посередині всіх цих шляхів
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR]-() } > 0
RETURN u.userId AS userId, COUNT { (u)-[:SIMILAR]-() } AS similar_neighbours,
       COUNT { (u)-[:RATED]->() } AS ratings
ORDER BY similar_neighbours DESC, userId
LIMIT 3;

// Що лишиться без найбільшого хаба: зв'язність графа SIMILAR без користувача 4277
CALL gds.graph.project.cypher('noHub',
  'MATCH (u:User) WHERE u.userId <> 4277 AND COUNT { (u)-[:SIMILAR]-() } > 0 RETURN id(u) AS id',
  'MATCH (a:User)-[:SIMILAR]->(b:User) WHERE a.userId <> 4277 AND b.userId <> 4277 RETURN id(a) AS source, id(b) AS target',
  { validateRelationships: false })
YIELD nodeCount, relationshipCount;
CALL gds.wcc.stats('noHub')
YIELD componentCount, componentDistribution
RETURN componentCount, componentDistribution.max AS largest_component;
CALL gds.graph.drop('noHub') YIELD graphName RETURN graphName;

// Прибирання
CALL gds.graph.drop('userGraph') YIELD graphName RETURN graphName;
MATCH ()-[sim:SIMILAR]-() DELETE sim;

// ============================================================
// 5.2-5.3, варіант B: схожість Жаккара замість сирої кількості спільних фільмів
// ============================================================
// Сира кількість спільних оцінок 4-5 росте з активністю, тож 50 000 найважчих пар
// зібрали лише 1 222 найактивніших користувачів. Індекс Жаккара (спільні / усі вподобання
// обох) від активності не залежить. gds.nodeSimilarity рахує його на двочастковому
// графі "користувач - фільм з оцінкою 4-5" і для кожного користувача лишає 10 найсхожіших.
CALL gds.graph.project.cypher(
  'likes',
  'MATCH (n) WHERE n:User OR n:Movie RETURN id(n) AS id, labels(n) AS labels',
  'MATCH (u:User)-[r:RATED]->(m:Movie) WHERE r.rating >= 4 RETURN id(u) AS source, id(m) AS target'
)
YIELD graphName, nodeCount, relationshipCount;

CALL gds.nodeSimilarity.write('likes', {
  topK: 10, writeRelationshipType: 'SIMILAR_JACCARD', writeProperty: 'jaccard'
})
YIELD nodesCompared, relationshipsWritten;

CALL gds.graph.drop('likes') YIELD graphName RETURN graphName;

// Взаємні сусіди дають два зустрічні ребра; aggregation SINGLE лишає одне
CALL gds.graph.project(
  'userJaccard',
  'User',
  { SIMILAR_JACCARD: { orientation: 'UNDIRECTED', aggregation: 'SINGLE', properties: 'jaccard' } }
)
YIELD graphName, nodeCount, relationshipCount;

CALL gds.louvain.write('userJaccard', {
  relationshipWeightProperty: 'jaccard', writeProperty: 'community_jaccard',
  concurrency: 1
})
YIELD communityCount, modularity, ranLevels;

// 10 найбільших спільнот: розмір, частка жінок, найчастіша вікова група, активність
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR_JACCARD]-() } > 0
WITH u.community_jaccard AS community, u
WITH community, count(*) AS users,
     round(100.0 * sum(CASE WHEN u.gender = 'F' THEN 1 ELSE 0 END) / count(*), 1) AS women_pct,
     round(avg(COUNT { (u)-[:RATED]->() })) AS avg_ratings_per_user,
     collect(u.ageGroup) AS ages
UNWIND ages AS age
WITH community, users, women_pct, avg_ratings_per_user, age, count(*) AS n
ORDER BY community, n DESC, age
WITH community, users, women_pct, avg_ratings_per_user, collect(age)[0] AS top_age_group
RETURN community, users, women_pct, top_age_group, avg_ratings_per_user
ORDER BY users DESC, community
LIMIT 10;

// Для порівняння: частка жінок серед усіх користувачів
MATCH (u:User)
RETURN round(100.0 * sum(CASE WHEN u.gender = 'F' THEN 1 ELSE 0 END) / count(*), 1) AS women_pct_overall;

// Топ-3 жанри за кількістю і три найхарактерніші жанри (lift) для 10 найбільших спільнот
MATCH (:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE r.rating >= 4
WITH g.name AS genre, count(*) AS n
WITH collect([genre, n]) AS overall, sum(n) AS total
MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR_JACCARD]-() } > 0
WITH overall, total, u.community_jaccard AS community, count(*) AS users
ORDER BY users DESC, community
LIMIT 10
WITH overall, total, collect(community) AS top_communities
MATCH (u:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE u.community_jaccard IN top_communities AND r.rating >= 4
WITH overall, total, u.community_jaccard AS community, g.name AS genre, count(*) AS n
ORDER BY community, n DESC, genre
WITH overall, total, community, collect([genre, n]) AS rows, sum(n) AS community_total
WITH overall, total, community, community_total, [row IN rows[0..3] | row[0]] AS top3_by_count,
     [row IN rows WHERE row[1] >= 50 |
       [row[0], (toFloat(row[1]) / community_total) / (toFloat([o IN overall WHERE o[0] = row[0]][0][1]) / total)]] AS lifts
UNWIND lifts AS lift
WITH community, top3_by_count, lift ORDER BY community, lift[1] DESC
WITH community, top3_by_count, collect(lift[0] + ' x' + toString(round(lift[1], 2)))[0..3] AS most_distinctive
RETURN community, top3_by_count, most_distinctive
ORDER BY community;

// Шлях між користувачами на графі Жаккара: зв'язність і середня кількість кроків
CALL gds.wcc.stats('userJaccard')
YIELD componentCount, componentDistribution
RETURN componentCount, componentDistribution.max AS largest_component;

MATCH (u:User)
WHERE COUNT { (u)-[:SIMILAR_JACCARD]-() } > 0
WITH u ORDER BY u.userId
WITH collect(u) AS users
UNWIND range(0, 19) AS i
WITH users[(i * 7919) % size(users)] AS source
CALL gds.allShortestPaths.dijkstra.stream('userJaccard', { sourceNode: source })
YIELD targetNode, totalCost
WHERE gds.util.asNode(targetNode) <> source
RETURN count(*) AS paths, round(avg(totalCost), 2) AS avg_hops, max(totalCost) AS max_hops,
       sum(CASE WHEN totalCost > 6 THEN 1 ELSE 0 END) AS longer_than_6;

// Ті самі пари користувачів, що й у варіанті A
UNWIND [[19, 23], [19, 42], [23, 42], [19, 4277]] AS pair
MATCH (source:User {userId: pair[0]}), (target:User {userId: pair[1]})
CALL gds.shortestPath.dijkstra.stream('userJaccard', { sourceNode: source, targetNode: target })
YIELD totalCost, nodeIds
RETURN source.userId AS from_user, target.userId AS to_user, toInteger(totalCost) AS hops,
       [n IN gds.util.asNodes(nodeIds) | n.userId] AS chain;

// Прибирання
CALL gds.graph.drop('userJaccard') YIELD graphName RETURN graphName;
MATCH ()-[s:SIMILAR_JACCARD]->() DELETE s;
