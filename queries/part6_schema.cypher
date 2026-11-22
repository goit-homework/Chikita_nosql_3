// queries/part6_schema.cypher
// Виміри до частини 6.3: як зміни схеми прискорюють запити 3 і 5 з частини 3.
// Запуск: cat queries/part6_schema.cypher | docker exec -i neo4j_movielens cypher-shell -u neo4j -p password123 --format verbose
// Скрипт сам прибирає за собою ребра LIKED і SIMILAR_JACCARD.

CALL gds.graph.drop('likes', false) YIELD graphName RETURN graphName;
MATCH ()-[l:LIKED]->() DELETE l;
MATCH ()-[s:SIMILAR_JACCARD]->() DELETE s;

// ============================================================
// Зміна 1: окремий тип ребра LIKED для оцінок 4-5
// ============================================================
CALL apoc.periodic.iterate(
  "MATCH (u:User)-[r:RATED]->(m:Movie) WHERE r.rating >= 4 RETURN u, m",
  "MERGE (u)-[:LIKED]->(m)",
  {batchSize: 10000, parallel: false}
)
YIELD batches, total
RETURN batches, total AS liked_edges;

// Запит 3 наживо: фільтр за властивістю кожного ребра
PROFILE
MATCH (:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(:User {userId: 2})
WHERE r1.rating >= 4 AND r2.rating >= 4
RETURN count(m) AS both_liked;

// Запит 3 через LIKED: фільтр за типом ребра
PROFILE
MATCH (:User {userId: 1})-[:LIKED]->(m:Movie)<-[:LIKED]-(:User {userId: 2})
RETURN count(m) AS both_liked;

// Запит 5 наживо, як у part3.cypher
PROFILE
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
WITH rec, sum(jaccard) AS score, count(other) AS similar_users
RETURN rec.title AS title, rec.year AS year, round(score, 3) AS score, similar_users
ORDER BY score DESC, similar_users DESC, title
LIMIT 5;

// Запит 5 через LIKED: ступінь за типом ребра Neo4j бере зі збереженого лічильника
PROFILE
MATCH (target:User {userId: 1})
WITH target, COUNT { (target)-[:LIKED]->() } AS target_likes
MATCH (target)-[:LIKED]->(m:Movie)<-[:LIKED]-(other:User)
WITH target, target_likes, other, count(m) AS shared_likes
WITH target, other, shared_likes, target_likes,
     COUNT { (other)-[:LIKED]->() } AS other_likes
WITH target, other, toFloat(shared_likes) / (target_likes + other_likes - shared_likes) AS jaccard
ORDER BY jaccard DESC, other.userId
LIMIT 25
MATCH (other)-[:LIKED]->(rec:Movie)
WHERE NOT (target)-[:RATED]->(rec)
WITH rec, sum(jaccard) AS score, count(other) AS similar_users
RETURN rec.title AS title, rec.year AS year, round(score, 3) AS score, similar_users
ORDER BY score DESC, similar_users DESC, title
LIMIT 5;

// ============================================================
// Зміна 2: передобчислена схожість SIMILAR_JACCARD (10 сусідів на користувача)
// ============================================================
CALL gds.graph.project.cypher(
  'likes',
  'MATCH (n) WHERE n:User OR n:Movie RETURN id(n) AS id, labels(n) AS labels',
  'MATCH (u:User)-[:LIKED]->(m:Movie) RETURN id(u) AS source, id(m) AS target'
)
YIELD graphName, nodeCount, relationshipCount;

CALL gds.nodeSimilarity.write('likes', {
  topK: 10, writeRelationshipType: 'SIMILAR_JACCARD', writeProperty: 'jaccard'
})
YIELD nodesCompared, relationshipsWritten;

CALL gds.graph.drop('likes') YIELD graphName RETURN graphName;

// Запит 5 на передобчисленій схожості: сусіди - один крок, їхні фільми - другий
PROFILE
MATCH (target:User {userId: 1})-[s:SIMILAR_JACCARD]->(other:User)
MATCH (other)-[:LIKED]->(rec:Movie)
WHERE NOT (target)-[:RATED]->(rec)
WITH rec, sum(s.jaccard) AS score, count(other) AS similar_users
RETURN rec.title AS title, rec.year AS year, round(score, 3) AS score, similar_users
ORDER BY score DESC, similar_users DESC, title
LIMIT 5;

// Прибирання
MATCH ()-[s:SIMILAR_JACCARD]->() DELETE s;
CALL apoc.periodic.iterate(
  "MATCH ()-[l:LIKED]->() RETURN l",
  "DELETE l",
  {batchSize: 10000, parallel: false}
)
YIELD batches, total
RETURN batches, total AS liked_deleted;
