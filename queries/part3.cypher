// queries/part3.cypher
// Запуск: cat queries/part3.cypher | docker exec -i neo4j_movielens cypher-shell -u neo4j -p password123
// Сортування скрізь має другий ключ, щоб при рівних значеннях порядок не змінювався між запусками.

// ------------------------------------------------------------
// Запит 1. Фільми жанру Thriller із середнім рейтингом вище 4.0
// ------------------------------------------------------------
MATCH (:Genre {name: 'Thriller'})<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-(:User)
WITH m, avg(r.rating) AS avg_rating, count(r) AS ratings
WHERE avg_rating > 4.0
RETURN m.title AS title, m.year AS year, round(avg_rating, 3) AS avg_rating, ratings
ORDER BY avg_rating DESC, ratings DESC, title;

// Скільки з них відрізняються від порогу 4.0 менше, ніж на статистичну похибку:
// 95% довірчий інтервал середнього (середнє ± 1.96 · stDev / √n) захоплює 4.0
MATCH (:Genre {name: 'Thriller'})<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-(:User)
WITH m, avg(r.rating) AS avg_rating, stDev(r.rating) AS sd, count(r) AS ratings
WHERE avg_rating > 4.0
RETURN count(*) AS films, min(ratings) AS min_ratings, max(ratings) AS max_ratings,
       sum(CASE WHEN avg_rating - 1.96 * sd / sqrt(ratings) <= 4.0 THEN 1 ELSE 0 END) AS ci_includes_4;

// ------------------------------------------------------------
// Запит 2. Користувачі, які поставили оцінку 5 більш ніж 50 фільмам
// ------------------------------------------------------------
MATCH (u:User)-[r:RATED]->(:Movie)
WHERE r.rating = 5
WITH u, count(r) AS five_star_ratings
WHERE five_star_ratings > 50
RETURN u.userId AS userId, u.gender AS gender, u.ageGroup AS age_group,
       u.occupationName AS occupation, five_star_ratings
ORDER BY five_star_ratings DESC, userId;

// Скільки таких користувачів усього
MATCH (u:User)-[r:RATED]->(:Movie)
WHERE r.rating = 5
WITH u, count(r) AS five_star_ratings
WHERE five_star_ratings > 50
RETURN count(u) AS users_with_more_than_50_fives;

// ------------------------------------------------------------
// Запит 3. Фільми, які обидва користувачі (1 і 2) оцінили на 4 або 5
// Другий ключ сортування - рік: після відділення року назви фільмів не унікальні.
// ------------------------------------------------------------
MATCH (m:Movie)
WITH m.title AS title, collect(m.year) AS years
WHERE size(years) > 1
RETURN count(*) AS titles_shared_by_several_movies, collect([title, years])[0..3] AS examples;

MATCH (u1:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User {userId: 2})
WHERE r1.rating >= 4 AND r2.rating >= 4
RETURN m.title AS title, m.year AS year, r1.rating AS user1_rating, r2.rating AS user2_rating
ORDER BY title, year;

// ------------------------------------------------------------
// Запит 4. Жанри, чиї фільми стабільно отримують високі оцінки
// Окрім середнього і кількості, рахуємо частку оцінок 4-5 і розкид (stDev):
// "стабільно" означає не лише високе середнє, а й мало низьких оцінок.
// ------------------------------------------------------------
MATCH (g:Genre)<-[:HAS_GENRE]-(:Movie)<-[r:RATED]-(:User)
WITH g, avg(r.rating) AS avg_rating, count(r) AS ratings, stDev(r.rating) AS rating_stdev,
     sum(CASE WHEN r.rating >= 4 THEN 1 ELSE 0 END) AS high_ratings
RETURN g.name AS genre,
       round(avg_rating, 3) AS avg_rating,
       ratings,
       round(100.0 * high_ratings / ratings, 1) AS high_share_pct,
       round(rating_stdev, 3) AS rating_stdev
ORDER BY avg_rating DESC, genre;

// Те саме на рівні фільмів: середня оцінка фільмів жанру і розкид цих середніх.
// Запит вище зважує кожну оцінку, тож у ньому домінують фільми з тисячами оцінок.
// Тут кожен фільм з 20+ оцінками важить однаково.
MATCH (g:Genre)<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-(:User)
WITH g, m, avg(r.rating) AS film_avg, count(r) AS ratings
WHERE ratings >= 20
WITH g, count(m) AS films, avg(film_avg) AS mean_film_avg, stDev(film_avg) AS film_avg_stdev
RETURN g.name AS genre, films, round(mean_film_avg, 3) AS mean_film_avg, round(film_avg_stdev, 3) AS film_avg_stdev
ORDER BY mean_film_avg DESC, genre;

// ------------------------------------------------------------
// Запит 5. "Користувачі зі схожими смаками також дивилися" для userId = 1
// 1) схожість - індекс Жаккара за фільмами, оціненими на 4-5:
//    спільні вподобання / усі вподобання обох користувачів;
// 2) беремо 25 найближчих сусідів;
// 3) рекомендуємо фільми, які сусіди оцінили на 4-5, а цільовий користувач ще не оцінював;
// 4) score - сума схожостей сусідів, що рекомендують фільм.
// ------------------------------------------------------------
MATCH (target:User {userId: 1})
WITH target, COUNT { (target)-[r:RATED]->() WHERE r.rating >= 4 } AS target_likes
MATCH (target)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(other:User)
WHERE r1.rating >= 4 AND r2.rating >= 4
WITH target, target_likes, other, count(m) AS shared_likes
WITH target, other, shared_likes, target_likes,
     COUNT { (other)-[r:RATED]->() WHERE r.rating >= 4 } AS other_likes
WITH target, other, toFloat(shared_likes) / (target_likes + other_likes - shared_likes) AS jaccard
ORDER BY jaccard DESC, other.userId
LIMIT 25
MATCH (other)-[r:RATED]->(rec:Movie)
WHERE r.rating >= 4 AND NOT (target)-[:RATED]->(rec)
WITH rec, sum(jaccard) AS score, count(other) AS similar_users, avg(r.rating) AS their_avg_rating
RETURN rec.title AS title, rec.year AS year, round(score, 3) AS score,
       similar_users, round(their_avg_rating, 2) AS their_avg_rating
ORDER BY score DESC, similar_users DESC, title
LIMIT 10;

// ------------------------------------------------------------
// Запит 6. Найкоротший ланцюжок між двома користувачами через спільні фільми
// Лише ребра RATED і без стрілки: від користувача до користувача шлях іде
// і за напрямком ребра, і проти нього. Без обмеження типу шлях міг би пройти через Genre.
// ------------------------------------------------------------
// Користувачі 1 і 2 мають спільний фільм
MATCH (a:User {userId: 1}), (b:User {userId: 2})
MATCH p = shortestPath((a)-[:RATED*..10]-(b))
RETURN a.userId AS from_user, b.userId AS to_user, length(p) AS path_length,
       [n IN nodes(p) | coalesce(n.title, 'User ' + toString(n.userId))] AS chain;

// Користувач 46 не має з користувачем 1 жодного спільного фільму
MATCH (a:User {userId: 1}), (b:User {userId: 46})
MATCH p = shortestPath((a)-[:RATED*..10]-(b))
RETURN a.userId AS from_user, b.userId AS to_user, length(p) AS path_length,
       [n IN nodes(p) | coalesce(n.title, 'User ' + toString(n.userId))] AS chain;
