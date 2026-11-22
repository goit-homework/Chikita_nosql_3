-- queries/part6_sql_comparison.sql
-- Ті самі дані MovieLens 1M у PostgreSQL для порівняння в частині 6.
-- Запуск з кореня репозиторію (після convert.py), будь-який PostgreSQL 14+:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f queries/part6_sql_comparison.sql

DROP TABLE IF EXISTS ratings, movie_genres, movies, users;

CREATE TABLE users (
    user_id    INTEGER PRIMARY KEY,
    gender     TEXT,
    age        INTEGER,
    occupation INTEGER
);
CREATE TABLE movies (
    movie_id INTEGER PRIMARY KEY,
    title    TEXT,
    genres   TEXT
);
CREATE TABLE ratings (
    user_id  INTEGER REFERENCES users,
    movie_id INTEGER REFERENCES movies,
    rating   INTEGER,
    ts       BIGINT,
    PRIMARY KEY (user_id, movie_id)
);

\copy users FROM 'import/users.csv' WITH (FORMAT csv, HEADER true)
\copy movies FROM 'import/movies.csv' WITH (FORMAT csv, HEADER true)
\copy ratings FROM 'import/ratings.csv' WITH (FORMAT csv, HEADER true)

-- Жанри: рядок "Animation|Children's|Comedy" -> окремі рядки, як вузли Genre у графі
CREATE TABLE movie_genres AS
SELECT movie_id, string_to_table(genres, '|') AS genre FROM movies;
CREATE INDEX ON movie_genres (genre);
CREATE INDEX ON movie_genres (movie_id);
CREATE INDEX ON ratings (movie_id);
ANALYZE;

SELECT (SELECT count(*) FROM users) AS users, (SELECT count(*) FROM movies) AS movies,
       (SELECT count(*) FROM ratings) AS ratings, (SELECT count(*) FROM movie_genres) AS movie_genres;

\timing on

-- Запит 4: агрегація за жанрами по всіх оцінках (у графі - 6,3 млн звернень до бази)
SELECT g.genre,
       round(avg(r.rating), 3) AS avg_rating,
       count(*) AS ratings,
       round(100.0 * count(*) FILTER (WHERE r.rating >= 4) / count(*), 1) AS high_share_pct,
       round(stddev_samp(r.rating), 3) AS rating_stdev
FROM movie_genres g
JOIN ratings r USING (movie_id)
GROUP BY g.genre
ORDER BY avg_rating DESC, g.genre;
-- Ще 5 виконань у прогрітому стані без друку результату; у README медіана цих замірів
\echo 'Запит 4 ще 5 разів:'
\o /dev/null
\g
\g
\g
\g
\g
\o

-- Запит 1: трилери із середнім рейтингом понад 4.0
SELECT m.title, round(avg(r.rating), 3) AS avg_rating, count(*) AS ratings
FROM movie_genres g
JOIN ratings r USING (movie_id)
JOIN movies m USING (movie_id)
WHERE g.genre = 'Thriller'
GROUP BY m.movie_id, m.title
HAVING avg(r.rating) > 4.0
ORDER BY avg_rating DESC, ratings DESC, m.title
LIMIT 10;
\echo 'Запит 1 ще 5 разів:'
\o /dev/null
\g
\g
\g
\g
\g
\o

-- Запит 6: найкоротший ланцюжок користувач 1 -> користувач 46 через спільні фільми.
-- Рекурсивний CTE обходить двочастковий граф хвилями: користувачі -> їхні фільми ->
-- користувачі, що оцінили ці фільми, ... UNION (без ALL) викидає лише однакові рядки
-- (вид, id, глибина), інакше кожна хвиля множила б рядки на всі шляхи. Відвіданих вузлів
-- CTE не пам'ятає: вузол на новій глибині розгортається знову, і зупинитися, щойно ціль
-- знайдено, він теж не може. Глибину треба обмежити вручну.
WITH RECURSIVE wave(kind, id, depth) AS (
    SELECT 'user', 1, 0
  UNION
    SELECT CASE WHEN w.kind = 'user' THEN 'movie' ELSE 'user' END,
           CASE WHEN w.kind = 'user' THEN r.movie_id ELSE r.user_id END,
           w.depth + 1
    FROM wave w
    JOIN ratings r ON (w.kind = 'user' AND r.user_id = w.id)
                   OR (w.kind = 'movie' AND r.movie_id = w.id)
    WHERE w.depth < 4
)
SELECT min(depth) AS path_length FROM wave WHERE kind = 'user' AND id = 46;
\echo 'Запит 6 ще 5 разів:'
\o /dev/null
\g
\g
\g
\g
\g
\o

-- Розмір хвиль того самого CTE: скільки вузлів він розгортає на кожній глибині
-- і чи повертається на неї стартовий користувач 1
\timing off
WITH RECURSIVE wave(kind, id, depth) AS (
    SELECT 'user', 1, 0
  UNION
    SELECT CASE WHEN w.kind = 'user' THEN 'movie' ELSE 'user' END,
           CASE WHEN w.kind = 'user' THEN r.movie_id ELSE r.user_id END,
           w.depth + 1
    FROM wave w
    JOIN ratings r ON (w.kind = 'user' AND r.user_id = w.id)
                   OR (w.kind = 'movie' AND r.movie_id = w.id)
    WHERE w.depth < 4
)
SELECT depth, kind, count(*) AS nodes, count(*) FILTER (WHERE kind = 'user' AND id = 1) AS user_1
FROM wave
GROUP BY depth, kind
ORDER BY depth;
