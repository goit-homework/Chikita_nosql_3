// queries/part4_supernodes.cypher
// Запуск: cat queries/part4_supernodes.cypher | docker exec -i neo4j_movielens cypher-shell -u neo4j -p password123 --format verbose
// --format verbose друкує для PROFILE план і "Total database accesses".

// ============================================================
// Крок 1. Вузли з аномально великою кількістю ребер
// size((n)--()) у Neo4j 5 - синтаксична помилка, ступінь рахуємо через COUNT { }
// ============================================================
MATCH (n)
WITH n, labels(n)[0] AS label, COUNT { (n)--() } AS degree
RETURN label, coalesce(n.title, n.name, 'User ' + toString(n.userId)) AS node, degree
ORDER BY degree DESC, node
LIMIT 15;

// Що вважати аномальним: розподіл ступенів окремо для кожного типу вузлів
MATCH (m:Movie)
WITH COUNT { (m)<-[:RATED]-() } AS d
RETURN 'Movie, оцінок' AS degree_of, count(*) AS nodes, round(avg(d), 1) AS avg,
       percentileDisc(d, 0.5) AS median, percentileDisc(d, 0.99) AS p99, max(d) AS max
UNION ALL
MATCH (u:User)
WITH COUNT { (u)-[:RATED]->() } AS d
RETURN 'User, оцінок' AS degree_of, count(*) AS nodes, round(avg(d), 1) AS avg,
       percentileDisc(d, 0.5) AS median, percentileDisc(d, 0.99) AS p99, max(d) AS max
UNION ALL
MATCH (g:Genre)
WITH COUNT { (g)<-[:HAS_GENRE]-() } AS d
RETURN 'Genre, фільмів' AS degree_of, count(*) AS nodes, round(avg(d), 1) AS avg,
       percentileDisc(d, 0.5) AS median, percentileDisc(d, 0.99) AS p99, max(d) AS max;

// Ті самі ступені лише для оцінених фільмів: 177 фільмів не мають жодної оцінки
MATCH (m:Movie)
WITH COUNT { (m)<-[:RATED]-() } AS d
WHERE d > 0
RETURN count(*) AS rated_movies, round(avg(d), 1) AS avg, percentileCont(d, 0.5) AS median;

// Ступінь вузла рахує всі ребра: в American Beauty це оцінки плюс два жанри
MATCH (m:Movie {movieId: 2858})
RETURN m.title AS movie, COUNT { (m)--() } AS degree, COUNT { (m)<-[:RATED]-() } AS ratings,
       COUNT { (m)-[:HAS_GENRE]->() } AS genres;

// Жанри: скільки фільмів у кожного і скільки оцінок за два кроки від нього
MATCH (movie:Movie)
WITH count(movie) AS movies_total
MATCH (g:Genre)
WITH g, movies_total, COUNT { (g)<-[:HAS_GENRE]-() } AS movies
RETURN g.name AS genre, movies,
       round(100.0 * movies / movies_total, 1) AS share_of_movies_pct,
       COUNT { (g)<-[:HAS_GENRE]-(:Movie)<-[:RATED]-() } AS ratings_two_hops
ORDER BY movies DESC, genre;

// ============================================================
// Крок 2. Чому запит через супервузол повільніший
// Той самий запит для American Beauty (3 428 оцінок) і для Kull the Conqueror
// (109 оцінок, медіанний фільм). Обидва фільми знаходяться через унікальний індекс movieId.
// ============================================================
PROFILE
MATCH (m:Movie {movieId: 2858})<-[r:RATED]-(u:User)
WHERE u.ageGroup = 'Under 18'
RETURN m.title AS movie, count(r) AS ratings_under_18, round(avg(r.rating), 3) AS avg_rating;

PROFILE
MATCH (m:Movie {movieId: 1606})<-[r:RATED]-(u:User)
WHERE u.ageGroup = 'Under 18'
RETURN m.title AS movie, count(r) AS ratings_under_18, round(avg(r.rating), 3) AS avg_rating;

// ============================================================
// Крок 3. Стратегії
// ============================================================

// --- Стратегія "фільтр через індекс до обходу" ---
// Індекс на властивість сусідів сам план не змінює: планувальник далі
// розгортає всі 3 428 ребер фільму. З підказкою USING INDEX він однаково їх розгортає,
// але з'єднує з 222 підлітками з індексу (NodeHashJoin) і не читає вік кожного глядача.
CREATE INDEX user_age_group IF NOT EXISTS FOR (u:User) ON (u.ageGroup);
CALL db.awaitIndexes(300);

PROFILE
MATCH (m:Movie {movieId: 2858})<-[r:RATED]-(u:User)
WHERE u.ageGroup = 'Under 18'
RETURN m.title AS movie, count(r) AS ratings_under_18, round(avg(r.rating), 3) AS avg_rating;

PROFILE
MATCH (u:User {ageGroup: 'Under 18'}) USING INDEX u:User(ageGroup)
MATCH (u)-[r:RATED]->(m:Movie {movieId: 2858})
RETURN m.title AS movie, count(r) AS ratings_under_18, round(avg(r.rating), 3) AS avg_rating;

// Стільки ребер мусив би розгорнути план, що справді починається з підлітків
MATCH (u:User {ageGroup: 'Under 18'})-[r:RATED]->()
RETURN count(DISTINCT u) AS teens, count(r) AS teen_ratings;

// --- Партиціонування за часом: за який період оцінки ---
MATCH ()-[r:RATED]->()
RETURN date(datetime({epochSeconds: min(r.timestamp)})) AS first_rating,
       date(datetime({epochSeconds: max(r.timestamp)})) AS last_rating;

// --- Жанр як супервузол: драми 1995 року ---
// Планувальник сам починає з індексу на рік (342 фільми) і перевіряє жанр кожного.
PROFILE
MATCH (m:Movie {year: 1995})-[:HAS_GENRE]->(:Genre {name: 'Drama'})
RETURN count(m) AS drama_1995;

// Для порівняння прохід через сам супервузол Drama: "+ 0" вимикає індекс на year.
PROFILE
MATCH (g:Genre {name: 'Drama'})
WITH g
MATCH (g)<-[:HAS_GENRE]-(m:Movie)
WHERE m.year + 0 = 1995
RETURN count(m) AS drama_1995;

// --- Стратегія "денормалізація агрегату" ---
// Кількість і середня оцінка зберігаються на вузлі фільму. Їх треба оновлювати
// при кожній новій оцінці, зате запити 1 і 4 більше не розгортають 1 млн ребер.
MATCH (m:Movie)
CALL {
  WITH m
  MATCH (m)<-[r:RATED]-()
  RETURN count(r) AS cnt, avg(r.rating) AS avg_r
}
SET m.ratingCount = cnt, m.avgRating = avg_r
RETURN count(m) AS movies_updated;

// Запит 1 наживо і з денормалізованим агрегатом
PROFILE
MATCH (:Genre {name: 'Thriller'})<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-(:User)
WITH m, avg(r.rating) AS avg_rating
WHERE avg_rating > 4.0
RETURN count(m) AS thrillers_above_4;

PROFILE
MATCH (:Genre {name: 'Thriller'})<-[:HAS_GENRE]-(m:Movie)
WHERE m.avgRating > 4.0
RETURN count(m) AS thrillers_above_4;

// Запит 4 наживо і з денормалізованим агрегатом (середнє, зважене кількістю оцінок)
PROFILE
MATCH (g:Genre)<-[:HAS_GENRE]-(:Movie)<-[r:RATED]-(:User)
WITH g, avg(r.rating) AS avg_rating, count(r) AS ratings
RETURN g.name AS genre, round(avg_rating, 3) AS avg_rating, ratings
ORDER BY avg_rating DESC, genre LIMIT 3;

PROFILE
MATCH (g:Genre)<-[:HAS_GENRE]-(m:Movie)
WHERE m.ratingCount > 0
WITH g, sum(m.avgRating * m.ratingCount) / sum(m.ratingCount) AS avg_rating, sum(m.ratingCount) AS ratings
RETURN g.name AS genre, round(avg_rating, 3) AS avg_rating, ratings
ORDER BY avg_rating DESC, genre LIMIT 3;
