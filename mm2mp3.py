import sqlite3
import tinytag

connection = sqlite3.connect('/home/dillen/tmp/MediaMonkey/MediaMonkey/files/mmstore.db')
cursor = connection.cursor()

for row in cursor.execute("SELECT _data, rating FROM media where rating > -1"):
    file = row[0]
    rating = row[1]

    print(f"{file}: {rating}")