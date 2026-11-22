// queries/part5_pair_counts.cypher
// Окремий підрахунок до 5.2: скільки пар користувачів мають багато спільних оцінок 4-5.
// Пояснює поріг weight >= 100 у part5_gds.cypher: якщо таких пар більше за 50 000,
// то 50 000 найважчих пар з умови повністю серед них, і поріг результату не змінює.
// Пари рахуються окремо для кожного користувача в CALL { }, як у part5_gds.cypher,
// інакше агрегація 190,8 млн рядків не вміщується в пам'ять. Близько 3,5 хв.
MATCH (u1:User)
CALL {
  WITH u1
  MATCH (u1)-[r1:RATED]->(:Movie)<-[r2:RATED]-(u2:User)
  WHERE r1.rating >= 4 AND r2.rating >= 4 AND elementId(u1) < elementId(u2)
  WITH u2, count(*) AS weight
  WHERE weight >= 100
  RETURN weight
}
RETURN count(*) AS pairs_ge_100,
       sum(CASE WHEN weight >= 150 THEN 1 ELSE 0 END) AS pairs_ge_150,
       sum(CASE WHEN weight >= 200 THEN 1 ELSE 0 END) AS pairs_ge_200,
       sum(CASE WHEN weight >= 300 THEN 1 ELSE 0 END) AS pairs_ge_300,
       max(weight) AS max_weight;
