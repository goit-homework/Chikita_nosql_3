// queries/part5_visualization.cypher
// Запити для скриншотів частини 5 у Neo4j Browser. Виконувати після part5_gds.cypher:
// вони беруть властивості pagerank і community_jaccard, які той записав у вузли.
// Вузли й ребра на картинках віртуальні (apoc.create.vNode, apoc.create.vRelationship):
// Browser малює їх як звичайні, але в базу нічого не пишеться. Мітки PR9, Romance, PathDoc
// тощо існують лише в результаті запиту, за ними Browser розфарбовує вузли.
// Ребра SIMILAR_JACCARD скрипт тимчасово відновлює тим самим викликом nodeSimilarity,
// що й part5_gds.cypher, і видаляє наприкінці.
//
// Стиль Browser: команда :style, а за нею в тому самому рядку цей текст.
// node {diameter: 50px; color: #A5ABB6; border-color: #9AA1AC; border-width: 2px; text-color-internal: #FFFFFF; font-size: 10px;}
// relationship {color: #A5ABB6; shaft-width: 1px; font-size: 13px; padding: 3px; text-color-external: #000000; text-color-internal: #FFFFFF; caption: '<type>';}
// relationship.CO_RATED {caption: '{weight}'; shaft-width: 2px;}
// relationship.SIMILAR_JACCARD {caption: ''; shaft-width: 1.5px; color: #9AA0A8;}
// relationship.PATH {caption: '{jaccard}'; shaft-width: 4px; color: #E8590C; font-size: 15px;}
// node.PR9 {diameter: 136px; color: #7B2D8E; border-color: #5E2270; text-color-internal: #FFFFFF; font-size: 15px; caption: '{title} PR {pagerank}';}
// node.PR7 {diameter: 120px; color: #A75BB8; border-color: #8A4399; text-color-internal: #FFFFFF; font-size: 14px; caption: '{title} PR {pagerank}';}
// node.PR6 {diameter: 110px; color: #D9B8E2; border-color: #B07CC0; text-color-internal: #2A2C34; font-size: 13px; caption: '{title} PR {pagerank}';}
// node.Romance {diameter: 80px; color: #F16667; border-color: #D93B3C; text-color-internal: #FFFFFF; font-size: 17px; caption: '{userId} {gender}';}
// node.SciFi {diameter: 80px; color: #4C8EDA; border-color: #2870C2; text-color-internal: #FFFFFF; font-size: 17px; caption: '{userId} {gender}';}
// node.Noir {diameter: 80px; color: #5B5F66; border-color: #3E4147; text-color-internal: #FFFFFF; font-size: 17px; caption: '{userId} {gender}';}
// node.PathAction {diameter: 110px; color: #FFC454; border-color: #E8590C; border-width: 4px; text-color-internal: #2A2C34; font-size: 17px; caption: 'User {userId} ({ratings})';}
// node.PathDoc {diameter: 110px; color: #8DCC93; border-color: #E8590C; border-width: 4px; text-color-internal: #2A2C34; font-size: 17px; caption: 'User {userId} ({ratings})';}
// node.Action {diameter: 58px; color: #FFE3A8; border-color: #E0B040; text-color-internal: #2A2C34; font-size: 13px; caption: '{userId}';}
// node.Doc {diameter: 58px; color: #CDEBD0; border-color: #6FB878; text-color-internal: #2A2C34; font-size: 13px; caption: '{userId}';}
// node.Other {diameter: 58px; color: #E2E4E8; border-color: #A5ABB6; text-color-internal: #2A2C34; font-size: 13px; caption: '{userId}';}
// Двокрапки в caption бути не може: парсер стилю ріже по ній, і підпис мовчки зникає.

// ============================================================
// 5.1. Десять фільмів з найвищим PageRank і по три найміцніші ребра CO_RATED кожного
// ============================================================
// Вага пари рахується так само, як CO_RATED у part5_gds.cypher: скільки користувачів
// оцінили обидва фільми на 4-5. Між десятьма фільмами всі 45 пар мають вагу від 886,
// тож без відбору граф був би суцільною сіткою. Розмір і колір вузла - рівень PageRank.
MATCH (m:Movie) WHERE m.pagerank IS NOT NULL
WITH m ORDER BY m.pagerank DESC LIMIT 10
WITH collect(m) AS top
WITH top, apoc.map.fromPairs([m IN top | [elementId(m), apoc.create.vNode(
       [CASE WHEN m.pagerank >= 9 THEN 'PR9' WHEN m.pagerank >= 7 THEN 'PR7' ELSE 'PR6' END],
       {title: m.title, pagerank: round(m.pagerank, 2)})]]) AS v
UNWIND top AS a
UNWIND top AS b
WITH v, a, b WHERE a <> b
MATCH (a)<-[r1:RATED]-(:User)-[r2:RATED]->(b)
WHERE r1.rating >= 4 AND r2.rating >= 4
WITH v, a, b, count(*) AS weight
ORDER BY weight DESC
WITH v, a, collect([b, weight])[0..3] AS strongest
UNWIND strongest AS s
// пара, яку обрали обидва фільми, лишається одним ребром
WITH v, CASE WHEN elementId(a) < elementId(s[0]) THEN [a, s[0]] ELSE [s[0], a] END AS pair, s[1] AS weight
WITH DISTINCT v, pair, weight
RETURN v[elementId(pair[0])] AS m1,
       apoc.create.vRelationship(v[elementId(pair[0])], 'CO_RATED', {weight: weight}, v[elementId(pair[1])]) AS co,
       v[elementId(pair[1])] AS m2;

// Для підпису в README: скільки пар серед десяти фільмів пов'язані і з якою вагою
MATCH (m:Movie) WHERE m.pagerank IS NOT NULL
WITH m ORDER BY m.pagerank DESC LIMIT 10
WITH collect(m) AS top
UNWIND top AS a
UNWIND top AS b
WITH a, b WHERE elementId(a) < elementId(b)
MATCH (a)<-[r1:RATED]-(:User)-[r2:RATED]->(b)
WHERE r1.rating >= 4 AND r2.rating >= 4
WITH a, b, count(*) AS weight
RETURN count(*) AS linked_pairs, min(weight) AS min_weight, max(weight) AS max_weight;

// Найважчі пари серед десяти фільмів, разом з тими, що не потрапили на картинку
MATCH (m:Movie) WHERE m.pagerank IS NOT NULL
WITH m ORDER BY m.pagerank DESC LIMIT 10
WITH collect(m) AS top
UNWIND top AS a
UNWIND top AS b
WITH a, b WHERE elementId(a) < elementId(b)
MATCH (a)<-[r1:RATED]-(:User)-[r2:RATED]->(b)
WHERE r1.rating >= 4 AND r2.rating >= 4
WITH a.title AS film_a, b.title AS film_b, count(*) AS weight
RETURN film_a, film_b, weight
ORDER BY weight DESC, film_a, film_b
LIMIT 12;

// ============================================================
// Граф Жаккара для 5.2 і 5.3: ті самі виклики, що й у part5_gds.cypher
// ============================================================
CALL gds.graph.drop('likes', false) YIELD graphName RETURN graphName;
CALL gds.graph.drop('userJaccard', false) YIELD graphName RETURN graphName;
MATCH ()-[s:SIMILAR_JACCARD]->() DELETE s;

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

CALL gds.graph.project(
  'userJaccard',
  'User',
  { SIMILAR_JACCARD: { orientation: 'UNDIRECTED', aggregation: 'SINGLE', properties: 'jaccard' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Для підпису в README: кожен обирає 10 найсхожіших, але в неорієнтованому графі
// до них додаються ті, хто обрав його самого
CALL gds.degree.stream('userJaccard')
YIELD nodeId, score
WITH gds.util.asNode(nodeId) AS u, score
WHERE score > 0
RETURN count(*) AS users, round(avg(score), 1) AS avg_neighbours,
       percentileDisc(score, 0.5) AS median_neighbours, max(score) AS max_neighbours,
       max(CASE WHEN u.userId = 4277 THEN score END) AS neighbours_4277;

// ============================================================
// 5.2. Три спільноти Louvain (варіант B): по 20 найзв'язніших користувачів кожної
// ============================================================
// Номери спільнот взято з виводу part5_gds.cypher: 3748 романтика, 4943 фантастика,
// 3169 нуар і документалістика. Після перезавантаження даних номери можуть бути іншими.
// "Найзв'язніші" - з найбільшою кількістю ребер SIMILAR_JACCARD усередині своєї спільноти.
// Показано всі ребра між обраними користувачами, і всередині спільнот, і між ними.
UNWIND [[3748, 'Romance'], [4943, 'SciFi'], [3169, 'Noir']] AS c
MATCH (u:User {community_jaccard: c[0]})
WITH c, u, COUNT { (u)-[:SIMILAR_JACCARD]-(o:User) WHERE o.community_jaccard = c[0] } AS inside
ORDER BY inside DESC, u.userId
WITH c, collect(u)[0..20] AS members
UNWIND members AS u
WITH collect([u, c[1]]) AS picked
WITH [p IN picked | p[0]] AS users,
     apoc.map.fromPairs([p IN picked | [elementId(p[0]), apoc.create.vNode([p[1]], {userId: p[0].userId, gender: p[0].gender})]]) AS v
UNWIND users AS a
MATCH (a)-[s:SIMILAR_JACCARD]->(b:User)
WHERE b IN users
RETURN v[elementId(a)] AS u1,
       apoc.create.vRelationship(v[elementId(a)], 'SIMILAR_JACCARD', {jaccard: round(s.jaccard, 3)}, v[elementId(b)]) AS sim,
       v[elementId(b)] AS u2;

// Для підпису в README: жінки серед 20 вибраних, ребра між вибраними, частка ребер між спільнотами
UNWIND [3748, 4943, 3169] AS c
MATCH (u:User {community_jaccard: c})
WITH c, u, COUNT { (u)-[:SIMILAR_JACCARD]-(o:User) WHERE o.community_jaccard = c } AS inside
ORDER BY inside DESC, u.userId
WITH c, collect(u)[0..20] AS members
RETURN c AS community, size([m IN members WHERE m.gender = 'F']) AS women_of_20,
       size([m IN members WHERE NOT EXISTS { (m)-[:SIMILAR_JACCARD]-(o:User) WHERE o IN members }]) AS without_edges_in_sample;

UNWIND [3748, 4943, 3169] AS c
MATCH (u:User {community_jaccard: c})
WITH c, u, COUNT { (u)-[:SIMILAR_JACCARD]-(o:User) WHERE o.community_jaccard = c } AS inside
ORDER BY inside DESC, u.userId
WITH c, collect(u)[0..20] AS members
UNWIND members AS u
WITH collect(u) AS users
UNWIND users AS a
MATCH (a)-[:SIMILAR_JACCARD]->(b:User)
WHERE b IN users
RETURN sum(CASE WHEN a.community_jaccard = b.community_jaccard THEN 1 ELSE 0 END) AS edges_inside,
       sum(CASE WHEN a.community_jaccard <> b.community_jaccard THEN 1 ELSE 0 END) AS edges_between;

// Найяскравіший профіль поза десяткою найбільших: невелика спільнота 4007 і жахи
MATCH (:User)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE r.rating >= 4
WITH g.name AS genre, count(*) AS n
WITH collect([genre, n]) AS overall, sum(n) AS total
MATCH (u:User {community_jaccard: 4007})
WITH overall, total, collect(u) AS members
UNWIND members AS u
MATCH (u)-[r:RATED]->(:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE r.rating >= 4
WITH overall, total, size(members) AS users, g.name AS genre, count(*) AS n
WITH overall, total, users, collect([genre, n]) AS rows, sum(n) AS community_total
UNWIND rows AS row
WITH users, row[0] AS genre,
     (toFloat(row[1]) / community_total) / (toFloat([o IN overall WHERE o[0] = row[0]][0][1]) / total) AS lift
RETURN users, genre, round(lift, 2) AS lift
ORDER BY lift DESC
LIMIT 3;

MATCH (a:User)-[:SIMILAR_JACCARD]->(b:User)
RETURN count(*) AS all_edges,
       round(100.0 * sum(CASE WHEN a.community_jaccard <> b.community_jaccard THEN 1 ELSE 0 END) / count(*), 1) AS between_communities_pct;

MATCH (a:User)-[:SIMILAR_JACCARD]->(b:User)
WHERE a.community_jaccard IN [3748, 4943, 3169] AND b.community_jaccard IN [3748, 4943, 3169]
RETURN count(*) AS edges_within_three,
       sum(CASE WHEN a.community_jaccard <> b.community_jaccard THEN 1 ELSE 0 END) AS edges_between_three;

// ============================================================
// 5.3. Шлях Дейкстри 19 -> 4277 на графі Жаккара і 10 найсхожіших сусідів кожного вузла шляху
// ============================================================
// Вузли шляху показують кількість оцінок, колір - спільнота (2538 бойовики, 5516 документалістика
// й нуар, сірі - решта). Ребро шляху має напрямок кроку. Якщо користувачі взаємно входять
// у топ-10 один одного, ребер два, з тією самою схожістю (Жаккар симетричний), і max() бере одне.
MATCH (source:User {userId: 19}), (target:User {userId: 4277})
CALL gds.shortestPath.dijkstra.stream('userJaccard', {sourceNode: source, targetNode: target})
YIELD nodeIds
WITH gds.util.asNodes(nodeIds) AS path
UNWIND path AS p
MATCH (p)-[:SIMILAR_JACCARD]->(n:User)
WHERE NOT n IN path
WITH path, collect(DISTINCT n) AS others
WITH path, others, apoc.map.fromPairs(
       [p IN path | [elementId(p), apoc.create.vNode(
         [CASE p.community_jaccard WHEN 2538 THEN 'PathAction' WHEN 5516 THEN 'PathDoc' ELSE 'PathOther' END],
         {userId: p.userId, ratings: COUNT { (p)-[:RATED]->() }})]] +
       [n IN others | [elementId(n), apoc.create.vNode(
         [CASE n.community_jaccard WHEN 2538 THEN 'Action' WHEN 5516 THEN 'Doc' ELSE 'Other' END],
         {userId: n.userId})]]) AS v
CALL {
  WITH path, v
  UNWIND range(0, size(path) - 2) AS i
  WITH path[i] AS a, path[i + 1] AS b, v
  MATCH (a)-[s:SIMILAR_JACCARD]-(b)
  WITH a, b, v, max(s.jaccard) AS j
  RETURN v[elementId(a)] AS u1,
         apoc.create.vRelationship(v[elementId(a)], 'PATH', {jaccard: round(j, 3)}, v[elementId(b)]) AS rel,
         v[elementId(b)] AS u2
  UNION ALL
  WITH path, others, v
  UNWIND path AS a
  MATCH (a)-[s:SIMILAR_JACCARD]->(b:User)
  WHERE b IN others
  RETURN v[elementId(a)] AS u1,
         apoc.create.vRelationship(v[elementId(a)], 'SIMILAR_JACCARD', {jaccard: round(s.jaccard, 3)}, v[elementId(b)]) AS rel,
         v[elementId(b)] AS u2
}
RETURN u1, rel, u2;

// Для підпису в README: активність уздовж шляху і скільки сусідів 19 з його спільноти.
// Індекс Жаккара не перевищує min(|A|, |B|) / max(|A|, |B|), тому для пари 19 - 4277
// він обмежений відношенням їхніх кількостей вподобань.
MATCH (source:User {userId: 19}), (target:User {userId: 4277})
CALL gds.shortestPath.dijkstra.stream('userJaccard', {sourceNode: source, targetNode: target})
YIELD nodeIds
UNWIND range(0, size(nodeIds) - 1) AS i
WITH i, gds.util.asNode(nodeIds[i]) AS u
RETURN i AS step, u.userId AS user, u.community_jaccard AS community, u.ageGroup AS age_group,
       COUNT { (u)-[:RATED]->() } AS ratings,
       COUNT { (u)-[r:RATED]->() WHERE r.rating >= 4 } AS likes,
       COUNT { (u)-[:SIMILAR_JACCARD]->(n:User) WHERE n.community_jaccard = u.community_jaccard } AS top10_in_own_community
ORDER BY step;

MATCH (a:User {userId: 19}), (b:User {userId: 4277})
WITH COUNT { (a)-[r:RATED]->() WHERE r.rating >= 4 } AS likes_19,
     COUNT { (b)-[r:RATED]->() WHERE r.rating >= 4 } AS likes_4277
RETURN likes_19, likes_4277, round(toFloat(likes_19) / likes_4277, 3) AS jaccard_upper_bound;

// Пряме ребро 19 - 4277 з'явилося б, лише якби їхня схожість дорівнювала хоча б найслабшому
// з 10 найсхожіших у когось із двох
UNWIND [19, 4277] AS id
MATCH (u:User {userId: id})-[s:SIMILAR_JACCARD]->(:User)
RETURN id AS user, round(min(s.jaccard), 3) AS weakest_of_top10, round(max(s.jaccard), 3) AS strongest_of_top10;

// Прибирання
CALL gds.graph.drop('userJaccard') YIELD graphName RETURN graphName;
MATCH ()-[s:SIMILAR_JACCARD]->() DELETE s;
