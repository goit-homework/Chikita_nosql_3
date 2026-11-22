// queries/part2_load.cypher
// Запуск: cat queries/part2_load.cypher | docker exec -i neo4j_movielens cypher-shell -u neo4j -p password123
// Скрипт ідемпотентний: MERGE не створює дублів при повторному запуску.

// ------------------------------------------------------------
// 0. Обмеження унікальності (кожне створює і індекс)
// Ставимо їх ще до вузлів: інакше кожен MERGE перебирав би всі вузли з цим лейблом.
// ------------------------------------------------------------
CREATE CONSTRAINT user_id IF NOT EXISTS FOR (u:User) REQUIRE u.userId IS UNIQUE;
CREATE CONSTRAINT movie_id IF NOT EXISTS FOR (m:Movie) REQUIRE m.movieId IS UNIQUE;
CREATE CONSTRAINT genre_name IF NOT EXISTS FOR (g:Genre) REQUIRE g.name IS UNIQUE;
// Для фільтрів за роком випуску в запитах
CREATE INDEX movie_year IF NOT EXISTS FOR (m:Movie) ON (m.year);
CALL db.awaitIndexes(300);

// ------------------------------------------------------------
// 1. Користувачі
// LOAD CSV читає все рядками, тому числа приводимо явно: інакше userId "1" і 1 були б різними ключами.
// age і occupation у MovieLens - коди; поруч зберігаємо їх розшифровку з README датасету.
// ------------------------------------------------------------
LOAD CSV WITH HEADERS FROM 'file:///users.csv' AS row
MERGE (u:User {userId: toInteger(row.userId)})
SET u.gender = row.gender,
    u.age = toInteger(row.age),
    u.ageGroup = {`1`: 'Under 18', `18`: '18-24', `25`: '25-34', `35`: '35-44',
                  `45`: '45-49', `50`: '50-55', `56`: '56+'}[row.age],
    u.occupation = toInteger(row.occupation),
    u.occupationName = ['other', 'academic/educator', 'artist', 'clerical/admin',
                        'college/grad student', 'customer service', 'doctor/health care',
                        'executive/managerial', 'farmer', 'homemaker', 'K-12 student', 'lawyer',
                        'programmer', 'retired', 'sales/marketing', 'scientist', 'self-employed',
                        'technician/engineer', 'tradesman/craftsman', 'unemployed', 'writer'][toInteger(row.occupation)];

// ------------------------------------------------------------
// 2. Фільми і жанри
// Рік стоїть у кінці назви: "Toy Story (1995)" -> title "Toy Story", year 1995.
// Жанри - рядок через |, розгортаємо його в окремі вузли Genre і ребра HAS_GENRE.
// ------------------------------------------------------------
LOAD CSV WITH HEADERS FROM 'file:///movies.csv' AS row
WITH row, trim(row.title) AS raw
WITH row, raw, raw =~ '.*\\(\\d{4}\\)$' AS hasYear
MERGE (m:Movie {movieId: toInteger(row.movieId)})
SET m.title = CASE WHEN hasYear THEN trim(substring(raw, 0, size(raw) - 6)) ELSE raw END,
    m.year = CASE WHEN hasYear THEN toInteger(substring(raw, size(raw) - 5, 4)) END
WITH m, row
UNWIND split(row.genres, '|') AS genreName
MERGE (g:Genre {name: genreName})
MERGE (m)-[:HAS_GENRE]->(g);

// ------------------------------------------------------------
// 3. Оцінки: 1 000 209 ребер RATED батчами по 10 000
// Вузли вже існують, тому в тілі лише MATCH за унікальними ключами (через індекси),
// а MERGE ребра захищає від дублів при повторному запуску.
// ------------------------------------------------------------
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM 'file:///ratings.csv' AS row RETURN row",
  "MATCH (u:User {userId: toInteger(row.userId)})
   MATCH (m:Movie {movieId: toInteger(row.movieId)})
   MERGE (u)-[r:RATED]->(m)
   SET r.rating = toInteger(row.rating),
       r.timestamp = toInteger(row.timestamp)",
  {batchSize: 10000, parallel: false}
)
YIELD batches, total, timeTaken, committedOperations, failedOperations, errorMessages
RETURN batches, total, timeTaken, committedOperations, failedOperations, errorMessages;

// ------------------------------------------------------------
// 4. Перевірка
// ------------------------------------------------------------
MATCH (u:User) RETURN count(u) AS users;
MATCH (m:Movie) RETURN count(m) AS movies;
MATCH ()-[r:RATED]->() RETURN count(r) AS ratings;
MATCH (g:Genre) RETURN count(g) AS genres;
MATCH ()-[h:HAS_GENRE]->() RETURN count(h) AS has_genre;
// дублів немає: кожна пара (користувач, фільм) має рівно одне ребро
MATCH (u:User)-[r:RATED]->(m:Movie)
WITH u, m, count(r) AS n
WHERE n > 1
RETURN count(*) AS duplicate_pairs;
MATCH (m:Movie) WHERE m.year IS NULL RETURN count(m) AS movies_without_year;
