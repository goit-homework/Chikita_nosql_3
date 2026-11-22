# convert.py - запустіть один раз перед завантаженням
# Читає .dat з розпакованого архіву ml-1m/ (роздільник ::, кодування Latin-1)
# і пише CSV з роздільником "," у кодуванні UTF-8 в теку import/.
import csv
import os

SRC = "ml-1m"
os.makedirs("import", exist_ok=True)

# movies.dat: MovieID::Title::Genres
with open(f'{SRC}/movies.dat', encoding='latin-1') as f_in, \
     open('import/movies.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['movieId', 'title', 'genres'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts)

# ratings.dat: UserID::MovieID::Rating::Timestamp
with open(f'{SRC}/ratings.dat', encoding='latin-1') as f_in, \
     open('import/ratings.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['userId', 'movieId', 'rating', 'timestamp'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts)

# users.dat: UserID::Gender::Age::Occupation::Zip
with open(f'{SRC}/users.dat', encoding='latin-1') as f_in, \
     open('import/users.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['userId', 'gender', 'age', 'occupation'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts[:4])  # zip не потрібен

for name in ('movies', 'ratings', 'users'):
    with open(f'import/{name}.csv', encoding='utf-8') as f:
        print(f"import/{name}.csv: {sum(1 for _ in f) - 1} рядків")
