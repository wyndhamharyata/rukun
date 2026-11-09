# Makes the test app's library: 5,000 songs, 400 albums by 150 artists, and a cover per album.
# Usage: python3 -I data/generate.py. The covers need ImageMagick 7 (magick).
# The same seed gives the same library.json. The output is committed, so the apps never run this.
import colorsys
import json
import random
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

SEED = 2026
SONG_COUNT = 5000
ALBUM_COUNT = 400
ARTIST_COUNT = 150
# The spec draws a cover at 180 points at most, on a 2x screen.
COVER_PIXELS = 360
MIN_SONGS_PER_ALBUM = 4
MAX_SONGS_PER_ALBUM = 24

HERE = Path(__file__).resolve().parent

FIRST_NAMES = """Ada Ayla Bram Cato Dara Elio Esme Faye Gale Hana Ilse Ines Jono Kaia Lark Lev Lina
Mara Milo Nell Noor Oren Pia Quin Rhea Rio Sana Tove Ula Vito Wren Yara Zane Ines Arlo Beto Cleo
Dov Edda Fenn Gita Hugo Iris Juno Kit Lior Maya Nico Odil Pax Rumi Sol Tali Uri Vera Wim Zoë""".split()

LAST_NAMES = """Abel Brandt Castell Dorne Ellery Fainn Garro Holm Iverly Jansky Kade Lindqvist Moreau
Nadal Okafor Pereira Quill Rask Sato Thorne Ueda Valen Weller Yoon Zeller Arden Bello Corvin
Dahl Eastly Finch Grey Hale Ito Kerr Lowe Marsh Novak Ortiz Pike Reyes Sauer Tamm Varga Wolfe
Åberg Müller Núñez Søndergaard""".split()

ADJECTIVES = """quiet silver golden hollow bright paper velvet distant electric slow broken wild
faded open northern southern crimson blue amber pale hidden gentle restless lonely endless
early late burning frozen secret little heavy weightless violet green neon tender honest
borrowed sudden brief last first lucky crooked painted wooden glass marble wandering sleepless
careless""".split()

NOUNS = """harbor lantern river window garden signal echo meadow highway station mirror ocean
orchard compass winter summer evening morning letter promise shadow island lighthouse planet
satellite city valley canyon desert forest thunder rain ember feather anchor ribbon circle
horizon tide season stranger fever heartbeat skyline postcard balcony staircase carousel
telephone radio paper engine moon sun star cloud field avenue bridge tower kingdom
mountain""".split()

PLURALS = """lanterns rivers windows gardens signals echoes mirrors oceans letters promises
shadows islands planets satellites cities valleys feathers anchors ribbons circles horizons
seasons strangers heartbeats skylines postcards engines stars clouds fields bridges towers
mountains""".split()

VERBS = """running falling dancing waiting drifting chasing calling holding leaving dreaming
burning sinking climbing turning breaking singing""".split()

PREPOSITIONS = "under over through beyond across behind after before into from".split()

PLACES = """Osaka Lisbon Reykjavik Montreal Nairobi Seoul Valparaíso Tallinn Bergen Kyoto
Marseille Hobart""".split()

JAPANESE = """夜明け 青い空 星の海 白い花 遠い街 雨の音 夏の終わり 光の中 風の歌 月の夜 小さな手紙 君の声
春の日 窓辺 夢の続き 静かな朝 さよならの前に 帰り道 ひかり あおぞら はなび ゆめ""".split()


def title_case(words):
    return ' '.join(word[:1].upper() + word[1:] for word in words)


def make_artist(rng):
    kind = rng.random()
    if kind < 0.55:
        return f'{rng.choice(FIRST_NAMES)} {rng.choice(LAST_NAMES)}'
    if kind < 0.8:
        return 'The ' + title_case([rng.choice(ADJECTIVES), rng.choice(PLURALS)])
    if kind < 0.92:
        return title_case([rng.choice(ADJECTIVES), rng.choice(NOUNS)])
    return rng.choice(JAPANESE[:12]) + rng.choice(['バンド', 'クラブ', 'の人たち', ''])


def make_title(rng, is_album):
    kind = rng.random()
    if kind < 0.05:
        return rng.choice(JAPANESE) + ('' if rng.random() < 0.6 else ' ' + rng.choice(JAPANESE))
    if kind < 0.1:
        return title_case([rng.choice(NOUNS)])
    if kind < 0.55:
        return title_case([rng.choice(ADJECTIVES), rng.choice(NOUNS)])
    if kind < 0.7:
        return title_case([rng.choice(VERBS), rng.choice(PREPOSITIONS), 'the', rng.choice(NOUNS)])
    if kind < 0.82:
        return title_case(['the', rng.choice(NOUNS), 'of', rng.choice(ADJECTIVES), rng.choice(PLURALS)])
    if kind < 0.9 or is_album:
        return title_case([rng.choice(ADJECTIVES), rng.choice(PLURALS)])
    # About 10% of songs have long titles, so the Title column truncates some rows.
    base = title_case([
        rng.choice(ADJECTIVES), rng.choice(NOUNS), rng.choice(PREPOSITIONS), 'the',
        rng.choice(ADJECTIVES), rng.choice(PLURALS),
    ])
    return f'{base} (Live in {rng.choice(PLACES)})' if rng.random() < 0.5 else base


def sort_key(text):
    return (text.casefold(), text)


def make_library(rng):
    artists = set()
    while len(artists) < ARTIST_COUNT:
        artists.add(make_artist(rng))
    artists = sorted(artists, key=sort_key)

    # Every artist has an album. The rest go to a few prolific artists more often.
    owners = list(artists) + rng.choices(artists, weights=[1 / (i + 1) ** 0.5 for i in range(ARTIST_COUNT)], k=ALBUM_COUNT - ARTIST_COUNT)
    albums = [{'title': make_title(rng, True), 'artist': artist, 'year': rng.randint(1978, 2026)} for artist in owners]
    albums.sort(key=lambda album: (sort_key(album['title']), sort_key(album['artist'])))
    for index, album in enumerate(albums):
        album['id'] = f'a{index + 1:04d}'
        album['cover'] = f'{album["id"]}.jpg'

    counts = [rng.randint(6, 18) for _ in albums]
    while sum(counts) != SONG_COUNT:
        index = rng.randrange(len(counts))
        step = 1 if sum(counts) < SONG_COUNT else -1
        if MIN_SONGS_PER_ALBUM <= counts[index] + step <= MAX_SONGS_PER_ALBUM:
            counts[index] += step

    songs = []
    for album, count in zip(albums, counts):
        for track in range(1, count + 1):
            seconds = int(min(540, max(95, rng.gauss(225, 50))))
            songs.append({
                'title': make_title(rng, False),
                'artist': album['artist'],
                'album': album['title'],
                'album_id': album['id'],
                'track': track,
                'seconds': seconds,
            })
    songs.sort(key=lambda song: (sort_key(song['title']), sort_key(song['artist']), song['album_id'], song['track']))
    for index, song in enumerate(songs):
        song['id'] = f's{index + 1:05d}'

    field_order = {'albums': ['id', 'title', 'artist', 'year', 'cover'], 'songs': ['id', 'title', 'artist', 'album', 'album_id', 'track', 'seconds']}
    return {
        name: [{key: item[key] for key in field_order[name]} for item in items]
        for name, items in (('albums', albums), ('songs', songs))
    }


def to_hex(hue, saturation, lightness):
    red, green, blue = colorsys.hls_to_rgb(hue % 1, lightness, saturation)
    return '#%02x%02x%02x' % (round(red * 255), round(green * 255), round(blue * 255))


def cover_command(rng, path):
    hue = rng.random()
    start = to_hex(hue, rng.uniform(0.45, 0.85), rng.uniform(0.25, 0.55))
    end = to_hex(hue + rng.uniform(0.08, 0.35), rng.uniform(0.45, 0.85), rng.uniform(0.15, 0.6))
    mark = to_hex(hue + 0.5, rng.uniform(0.3, 0.9), rng.uniform(0.6, 0.9))
    size = COVER_PIXELS
    command = [
        'magick', '-size', f'{size}x{size}', '-define', f'gradient:angle={rng.randrange(0, 360, 15)}',
        f'gradient:{start}-{end}',
    ]
    for _ in range(rng.randint(1, 3)):
        x, y = rng.randrange(size), rng.randrange(size)
        radius = rng.randrange(size // 10, size // 2)
        opacity = rng.uniform(0.25, 0.8)
        if rng.random() < 0.5:
            command += ['-fill', mark, '-stroke', 'none', '-draw', f'fill-opacity {opacity:.2f} circle {x},{y} {x + radius},{y}']
        else:
            width = rng.randrange(4, 24)
            command += ['-fill', 'none', '-stroke', mark, '-strokewidth', str(width), '-draw', f'stroke-opacity {opacity:.2f} circle {x},{y} {x + radius},{y}']
    command += ['-strip', '-quality', '85', str(path)]
    return command


def main():
    rng = random.Random(SEED)
    library = make_library(rng)

    lines = ['{']
    for name in ('albums', 'songs'):
        items = ',\n'.join('  ' + json.dumps(item, ensure_ascii=False) for item in library[name])
        lines.append(f' "{name}": [\n{items}\n ]' + (',' if name == 'albums' else ''))
    lines.append('}')
    (HERE / 'library.json').write_text('\n'.join(lines) + '\n', encoding='utf-8')

    covers = HERE / 'covers'
    shutil.rmtree(covers, ignore_errors=True)
    covers.mkdir()
    # The commands come from one seeded generator in a fixed order, then run in parallel.
    commands = [cover_command(rng, covers / album['cover']) for album in library['albums']]
    with ThreadPoolExecutor() as pool:
        for result in pool.map(lambda command: subprocess.run(command, check=True), commands):
            pass

    songs, albums = library['songs'], library['albums']
    assert len(songs) == SONG_COUNT and len(albums) == ALBUM_COUNT
    assert len({album['artist'] for album in albums}) == ARTIST_COUNT
    assert len({song['id'] for song in songs}) == SONG_COUNT
    per_album = {album['id']: 0 for album in albums}
    for song in songs:
        per_album[song['album_id']] += 1
    assert all(MIN_SONGS_PER_ALBUM <= count <= MAX_SONGS_PER_ALBUM for count in per_album.values())
    assert all((covers / album['cover']).stat().st_size > 0 for album in albums)

    print(f"{len(library['songs'])} songs, {len(library['albums'])} albums, {len({a['artist'] for a in library['albums']})} artists, {len(commands)} covers")


if __name__ == '__main__':
    main()
