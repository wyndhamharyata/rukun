# Makes the test app's data: one family's Rukun workspace over three years. 5 members, 12 spaces,
# 5,000 tasks, 200 notes, about 10,000 timeline items, 400 photos and an avatar per member.
# Usage: python3 -I data/generate.py. The images need ImageMagick 7 (magick).
# The same seed gives the same rukun.json. The output is committed, so the apps never run this.
import colorsys
import json
import random
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path

SEED = 2026
TASK_COUNT = 5000
NOTE_COUNT = 200
PHOTO_COUNT = 400
LONG_SPACE = 'keluarga'
LONG_SPACE_ITEMS = 4000
OTHER_SPACE_ITEMS = (300, 800)
START = datetime(2024, 1, 1)
TODAY = datetime(2026, 11, 9)
LAST_DUE = datetime(2027, 1, 31)
# The spec draws a photo at 240 by 180 points and an avatar at 28, on a 2x screen.
PHOTO_PIXELS = (480, 360)
AVATAR_PIXELS = 56

HERE = Path(__file__).resolve().parent

MEMBERS = [('m1', 'Nadia'), ('m2', 'Raka'), ('m3', 'Kayla'), ('m4', 'Bima'), ('m5', 'Oma Rini')]
KIDS = ['Kayla', 'Bima']
ADULTS = ['Nadia', 'Raka']
EVERYONE = [name for _, name in MEMBERS]

# Each space, who takes its tasks, and its task titles.
SPACES = {
    'sekolah': (ADULTS, [
        'Bayar SPP {kid}', 'Jemput {kid} di sekolah', 'Jemput {kid} dari les {les}', 'Cek PR {subject} {kid}',
        'Siapkan bekal {kid}', 'Beli {school_item} untuk {kid}', 'Daftarkan {kid} ke ekskul {extra}',
        'Datang ke rapat orang tua murid', 'Tanda tangan rapor {kid}', 'Antar {kid} ke {school_event}',
    ]),
    'rumah': (EVERYONE, [
        'Bayar PLN', 'Bayar PDAM', 'Bayar iuran RT', 'Ganti paket internet', 'Servis AC {room}', 'Bersihkan {room}',
        'Ganti lampu {room}', 'Panggil tukang untuk {repair}', 'Buang sampah', 'Cuci {laundry}', 'Beli galon',
        'Beli gas elpiji', 'Rapikan {room}',
    ]),
    'keuangan': (ADULTS, [
        'Bayar cicilan rumah', 'Bayar kartu kredit', 'Bayar asuransi {insurance}', 'Bayar BPJS keluarga',
        'Transfer uang jajan {kid}', 'Catat pengeluaran {month}', 'Lapor SPT tahunan', 'Perpanjang deposito',
        'Kirim uang bulanan untuk Oma',
    ]),
    'liburan': (ADULTS, [
        'Pesan tiket ke {dest}', 'Cari hotel di {dest}', 'Perpanjang paspor {person}', 'Siapkan koper ke {dest}',
        'Tukar uang untuk ke {dest}', 'Titipkan Mochi selama ke {dest}',
    ]),
    'kesehatan': (ADULTS + ['Oma Rini'], [
        'Kontrol gigi {person}', 'Vaksin {vaccine} untuk {kid}', 'Tebus resep obat Oma', 'Medical check-up {adult}',
        'Beli vitamin untuk {person}', 'Jadwalkan fisioterapi Oma',
    ]),
    'belanja': (ADULTS + ['Oma Rini'], [
        'Beli {grocery}', 'Belanja mingguan di {store}', 'Beli kado ulang tahun {person}', 'Pesan {grocery} online',
    ]),
    'mobil': (['Raka'], [
        'Servis rutin mobil', 'Ganti oli mobil', 'Bayar pajak mobil', 'Cuci mobil', 'Perpanjang SIM {adult}',
        'Isi angin ban', 'Ganti aki mobil',
    ]),
    'keluarga': (EVERYONE, [
        'Telepon Oma', 'Atur jadwal kumpul keluarga', 'Foto keluarga di {place}', 'Kirim kue ke rumah {relative}',
        'Ajak anak-anak ke {place}',
    ]),
    'resep': (['Nadia', 'Oma Rini'], [
        'Coba resep {dish}', 'Beli bahan {dish}', 'Masak {dish} untuk {event}',
    ]),
    'acara': (ADULTS + ['Kayla'], [
        'Siapkan ulang tahun {person}', 'Pesan kue untuk {event}', 'Kirim undangan {event}', 'Sewa tenda untuk {event}',
        'Konfirmasi tamu {event}',
    ]),
    'kucing': (KIDS + ['Nadia'], [
        'Beli pakan Mochi', 'Vaksin Mochi', 'Bersihkan pasir Mochi', 'Mandikan Mochi', 'Bawa Mochi ke dokter hewan',
    ]),
    'kebun': (['Oma Rini', 'Bima', 'Raka'], [
        'Siram tanaman cabai', 'Pangkas pohon mangga', 'Beli pupuk', 'Tanam bibit {plant}', 'Bersihkan kolam ikan',
    ]),
}

WORDS = {
    'kid': KIDS,
    'adult': ADULTS,
    'person': EVERYONE,
    'les': ['piano', 'renang', 'matematika', 'bahasa Inggris', 'gambar'],
    'subject': ['matematika', 'IPA', 'bahasa Indonesia', 'bahasa Inggris', 'IPS'],
    'school_item': ['seragam baru', 'buku gambar', 'sepatu sekolah', 'tas baru', 'alat tulis', 'buku paket'],
    'extra': ['futsal', 'pramuka', 'paduan suara', 'robotik', 'menari'],
    'school_event': ['karyawisata', 'lomba tujuh belasan', 'pentas seni', 'class meeting', 'manasik haji'],
    'room': ['kamar tidur', 'ruang tamu', 'dapur', 'kamar mandi', 'teras', 'kamar Kayla', 'kamar Bima', 'gudang'],
    'repair': ['atap bocor', 'keran rusak', 'pintu macet', 'saluran air', 'pagar berkarat'],
    'laundry': ['sprei', 'gorden', 'karpet', 'seragam', 'selimut'],
    'insurance': ['kesehatan', 'mobil', 'rumah', 'jiwa'],
    'month': ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'],
    'dest': ['Bali', 'Yogyakarta', 'Malang', 'Lombok', 'Bandung', 'Labuan Bajo', 'Singapura', 'Tokyo', 'Belitung'],
    'vaccine': ['influenza', 'tifoid', 'HPV', 'DBD', 'hepatitis A'],
    'grocery': ['beras', 'telur', 'minyak goreng', 'susu', 'sabun cuci', 'gula', 'kopi', 'buah', 'sayur', 'roti', 'deterjen', 'tisu'],
    'store': ['pasar', 'supermarket', 'toko sayur', 'minimarket'],
    'place': ['Kebun Raya', 'pantai', 'kebun binatang', 'taman kota', 'museum', 'puncak'],
    'relative': ['Tante Dewi', 'Om Hendra', 'Pakde Joko', 'Bude Sari', 'sepupu di Bekasi'],
    'dish': ['rendang', 'soto ayam', 'opor', 'nasi goreng kampung', 'sayur asem', 'bakwan jagung', 'klepon', 'sop buntut', 'ayam bakar', 'pepes ikan'],
    'event': ['arisan', 'Lebaran', 'ulang tahun Bima', 'ulang tahun Kayla', 'syukuran rumah', 'Natal kantor', 'reuni SMA'],
    'plant': ['tomat', 'cabai', 'kangkung', 'jeruk nipis', 'mawar', 'lidah buaya'],
    'day': ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'],
    'hour': ['11', '12', '13', '14', '15', '16', '17'],
}

TASK_SUFFIXES = [
    ' sebelum tanggal {date}', ' dan kirim buktinya ke grup', ' bareng {person} sepulang kerja',
    ' untuk persiapan {event} bulan depan', ' kalau sempat akhir pekan ini',
]

SENTENCES = [
    'Siap.', 'Oke, nanti aku kabari.', 'Makasih ya!', 'Sudah beres.', 'Aku pulang agak telat hari ini.',
    'Ada yang lihat kunci mobil?', 'Nanti malam makan di luar?', 'Jangan lupa bawa payung, katanya mau hujan.',
    'Aku sudah di jalan.', 'Tolong dicek lagi ya.', 'Nanti kita bahas pas makan malam.',
    'Boleh, asal PR-nya selesai dulu.', 'Wah, keren!', 'Aku setuju.', 'Besok saja ya, hari ini penuh.',
    'Sudah aku transfer.', 'Struknya aku simpan di laci dapur.', 'Siapa yang pakai charger terakhir?',
    '{kid} pulang jam {hour}.00.', 'Oma datang hari {day}.', '{person}, password wifi apa?',
    'Besok {kid} ada {school_event}.', 'Harga {grocery} naik lagi.', 'Kita berangkat ke {dest} tanggal {date}?',
    'Mochi muntah lagi, perlu ke dokter?', 'Aku masak {dish} malam ini.', 'Jangan lupa telepon {relative}.',
    'Tadi {kid} dapat nilai bagus di pelajaran {subject}.', 'Hari {day} aku ada rapat sampai sore, ada yang bisa jemput?',
    'Tolong matikan lampu {room} kalau sudah selesai.',
]

EMOJI = ['👍', '🙏', '😂', '❤️', '🎉', '😅', '🙌', '✅', '🚗', '🍜', '😴', '🐱']

PHOTO_SPACES = {'keluarga', 'liburan', 'acara', 'kucing', 'kebun', 'resep'}

LISTS = [
    ('Belanja mingguan', 'grocery'), ('Bahan {dish}', 'ingredient'), ('Barang bawaan ke {dest}', 'packing'),
    ('Perlengkapan sekolah {kid}', 'school_item'), ('Persiapan {event}', 'party'),
]

ENTRIES = {
    'grocery': WORDS['grocery'],
    'ingredient': ['bawang merah', 'bawang putih', 'cabai', 'santan', 'serai', 'daun salam', 'lengkuas', 'kemiri', 'jahe', 'kunyit'],
    'packing': ['paspor', 'charger', 'baju renang', 'obat-obatan', 'topi', 'sunscreen', 'kamera', 'sandal'],
    'school_item': WORDS['school_item'] + ['penggaris', 'pensil warna', 'botol minum'],
    'party': ['balon', 'kue', 'piring kertas', 'hadiah', 'lilin', 'minuman', 'undangan', 'dekorasi'],
}

NOTE_TITLES = {
    'rumah': ['Wi-Fi rumah', 'Nomor darurat', 'Tukang langganan', 'Jadwal sampah {year}', 'Cara reset router'],
    'sekolah': ['Kontak wali kelas {kid} {year}', 'Jadwal les {kid} {year}', 'Kalender sekolah {year}', 'Akun aplikasi sekolah {kid}'],
    'keuangan': ['Anggaran {month} {year}', 'Daftar tagihan bulanan', 'Rencana tabungan {year}'],
    'liburan': ['Rencana liburan {dest} {year}', 'Itinerary {dest}', 'Dokumen perjalanan'],
    'kesehatan': ['Daftar obat Oma', 'Dokter langganan', 'Riwayat vaksin {kid}', 'Golongan darah keluarga'],
    'belanja': ['Toko langganan', 'Ukuran baju anak {year}', 'Ide kado {person}'],
    'mobil': ['Catatan servis mobil {year}', 'Bengkel langganan', 'Asuransi mobil {year}'],
    'keluarga': ['Silsilah keluarga', 'Tanggal ulang tahun keluarga', 'Aturan screen time', 'Pembagian tugas rumah {year}'],
    'resep': ['Resep {dish}', 'Resep {dish} ala Oma'],
    'acara': ['Daftar tamu {event} {year}', 'Rundown {event} {year}'],
    'kucing': ['Jadwal vaksin Mochi', 'Makanan Mochi', 'Dokter hewan langganan'],
    'kebun': ['Tanaman di kebun', 'Jadwal pupuk {year}', 'Cara merawat {plant}'],
}

NOTE_SENTENCES = [
    'Simpan catatan ini supaya semua orang tahu.', 'Kalau ada perubahan, tulis di sini ya.',
    'Terakhir diperbarui oleh {person}.', 'Detailnya ada di grup, ini ringkasannya.',
    'Jangan dibagikan ke luar keluarga.', 'Tanyakan ke {person} kalau ada yang kurang jelas.',
    'Biasanya buka dari jam 8 pagi sampai jam 5 sore.', 'Bayar paling lambat tanggal 10 setiap bulan.',
    'Untuk {kid}, sesuaikan dengan jadwal sekolah.', 'Tahun lalu kita lupa, jadi tahun ini dicatat lebih awal.',
    'Bawa kartu identitas dan fotokopinya.', 'Konfirmasi lewat telepon sehari sebelumnya.',
    'Kalau hujan, rencananya pindah ke hari {day}.', 'Bahan-bahannya bisa dibeli di {store}.',
    'Takarannya untuk enam porsi.', 'Oma lebih suka yang tidak terlalu pedas.',
]


def fill(rng, template, extra=None):
    words = dict(extra or {})
    while '{' in template:
        start = template.index('{')
        end = template.index('}', start)
        key = template[start + 1:end]
        if key == 'date':
            value = f'{rng.randint(1, 28)} {rng.choice(WORDS["month"])}'
        elif key == 'year':
            value = str(rng.randint(2024, 2026))
        else:
            value = words[key] if key in words else rng.choice(WORDS[key])
        template = template[:start] + value + template[end + 1:]
    return template


def lower_first(text):
    return text[:1].lower() + text[1:] if text[1:2].islower() or text[1:2] == ' ' else text


def random_time(rng, start, end):
    return start + timedelta(seconds=rng.randrange(int((end - start).total_seconds())))


def make_tasks(rng, member_ids):
    space_names = list(SPACES)
    weights = [3, 4, 2, 1, 2, 3, 1, 2, 1, 1, 2, 1]
    tasks = []
    for _ in range(TASK_COUNT):
        space = rng.choices(space_names, weights)[0]
        people, templates = SPACES[space]
        title = fill(rng, rng.choice(templates))
        # About 10% of titles are long enough to end in an ellipsis.
        if rng.random() < 0.1:
            title += fill(rng, rng.choice(TASK_SUFFIXES))
        due = random_time(rng, START, LAST_DUE)
        is_done = due < TODAY and rng.random() < 0.96
        tasks.append({
            'title': title, 'space': space, 'assignee': member_ids[rng.choice(people)],
            'done': is_done, 'due': due.strftime('%Y-%m-%d'),
        })
    tasks.sort(key=lambda task: task['due'], reverse=True)
    for index, task in enumerate(tasks):
        task['id'] = f't{index + 1:05d}'
    return tasks


def make_notes(rng, tasks_by_space):
    notes = []
    titles = set()
    while len(notes) < NOTE_COUNT:
        space = rng.choice(list(NOTE_TITLES))
        title = fill(rng, rng.choice(NOTE_TITLES[space]))
        if title in titles:
            continue
        titles.add(title)
        body = [
            ' '.join(fill(rng, sentence) for sentence in rng.sample(NOTE_SENTENCES, rng.randint(1, 4)))
            for _ in range(rng.randint(1, 4))
        ]
        checklist = [
            {'text': entry, 'done': rng.random() < 0.5}
            for entry in rng.sample(ENTRIES[rng.choice(list(ENTRIES))], rng.randint(0, 5))
        ]
        related = [task['id'] for task in rng.sample(tasks_by_space[space], min(len(tasks_by_space[space]), rng.randint(0, 3)))]
        notes.append({'title': title, 'space': space, 'body': body, 'checklist': checklist, 'tasks': related})
    notes.sort(key=lambda note: note['title'].casefold())
    for index, note in enumerate(notes):
        note['id'] = f'n{index + 1:03d}'
    for note in notes:
        note['links'] = sorted({other['id'] for other in rng.sample(notes, rng.randint(0, 3)) if other is not note})
    return notes


def make_items(rng, space, count, member_ids, tasks, notes, photo_numbers):
    # People write between 6.00 and 22.59.
    days = sorted(random_time(rng, START, TODAY) for _ in range(count))
    times = sorted(day.replace(hour=rng.randint(6, 22)) for day in days)
    items = []
    for time in times:
        author = rng.choice(list(member_ids.values()))
        kind = rng.choices(['message', 'task', 'list', 'note'], [80, 10, 5, 5])[0]
        item = {'author': author, 'time': time.strftime('%Y-%m-%dT%H:%M'), 'kind': kind}
        if kind == 'message' or (kind == 'task' and not tasks) or (kind == 'note' and not notes):
            item['kind'] = 'message'
            count = rng.choices([1, 2, 3, 4], [50, 30, 15, 5])[0]
            text = ' '.join(fill(rng, sentence) for sentence in rng.sample(SENTENCES, count))
            if rng.random() < 0.15:
                text += ' ' + rng.choice(EMOJI)
            item['text'] = text
            if space in PHOTO_SPACES and photo_numbers and rng.random() < 0.08:
                item['photo'] = f'p{photo_numbers.pop():04d}.jpg'
        elif kind == 'task':
            item['task'] = rng.choice(tasks)['id']
        elif kind == 'note':
            item['note'] = rng.choice(notes)['id']
        else:
            title, entry_kind = rng.choice(LISTS)
            item['title'] = fill(rng, title)
            item['entries'] = [
                {'text': entry, 'done': rng.random() < 0.4}
                for entry in rng.sample(ENTRIES[entry_kind], rng.randint(3, min(8, len(ENTRIES[entry_kind]))))
            ]
        items.append(item)
    return items


def make_workspace(rng):
    member_ids = {name: member_id for member_id, name in MEMBERS}
    tasks = make_tasks(rng, member_ids)
    tasks_by_space = {space: [task for task in tasks if task['space'] == space] for space in SPACES}
    notes = make_notes(rng, tasks_by_space)
    notes_by_space = {space: [note for note in notes if note['space'] == space] for space in SPACES}

    # The long space gets the photos first, so scrolling it decodes most of them.
    photo_numbers = list(range(PHOTO_COUNT, 0, -1))
    spaces = []
    for space in [LONG_SPACE] + sorted(set(SPACES) - {LONG_SPACE}):
        count = LONG_SPACE_ITEMS if space == LONG_SPACE else rng.randint(*OTHER_SPACE_ITEMS)
        items = make_items(rng, space, count, member_ids, tasks_by_space[space], notes_by_space[space], photo_numbers)
        spaces.append({'id': space, 'name': space, 'items': items})
    spaces.sort(key=lambda space: space['name'])

    item_number = 0
    for space in spaces:
        for item in space['items']:
            item_number += 1
            item['id'] = f'i{item_number:05d}'

    for note in notes:
        note['in_spaces'] = sorted({space['id'] for space in spaces for item in space['items'] if item.get('note') == note['id']})
        note['in_notes'] = [other['id'] for other in notes if note['id'] in other['links']]

    members = [{'id': member_id, 'name': name, 'avatar': f'{member_id}.jpg'} for member_id, name in MEMBERS]
    order = {
        'tasks': ['id', 'title', 'space', 'assignee', 'done', 'due'],
        'notes': ['id', 'title', 'space', 'body', 'checklist', 'tasks', 'links', 'in_spaces', 'in_notes'],
    }
    tasks = [{key: task[key] for key in order['tasks']} for task in tasks]
    notes = [{key: note[key] for key in order['notes']} for note in notes]
    for space in spaces:
        space['items'] = [{'id': item.pop('id'), **item} for item in space['items']]
    return {'members': members, 'spaces': spaces, 'tasks': tasks, 'notes': notes}


def to_hex(hue, saturation, lightness):
    red, green, blue = colorsys.hls_to_rgb(hue % 1, lightness, saturation)
    return '#%02x%02x%02x' % (round(red * 255), round(green * 255), round(blue * 255))


def image_command(rng, path, width, height, shape_count):
    hue = rng.random()
    start = to_hex(hue, rng.uniform(0.45, 0.85), rng.uniform(0.25, 0.55))
    end = to_hex(hue + rng.uniform(0.08, 0.35), rng.uniform(0.45, 0.85), rng.uniform(0.15, 0.6))
    mark = to_hex(hue + 0.5, rng.uniform(0.3, 0.9), rng.uniform(0.6, 0.9))
    command = ['magick', '-size', f'{width}x{height}', '-define', f'gradient:angle={rng.randrange(0, 360, 15)}', f'gradient:{start}-{end}']
    for _ in range(shape_count):
        x, y = rng.randrange(width), rng.randrange(height)
        radius = rng.randrange(min(width, height) // 10, min(width, height) // 2)
        opacity = rng.uniform(0.25, 0.8)
        if rng.random() < 0.5:
            command += ['-fill', mark, '-stroke', 'none', '-draw', f'fill-opacity {opacity:.2f} circle {x},{y} {x + radius},{y}']
        else:
            stroke = rng.randrange(4, 24)
            command += ['-fill', 'none', '-stroke', mark, '-strokewidth', str(stroke), '-draw', f'stroke-opacity {opacity:.2f} circle {x},{y} {x + radius},{y}']
    return command + ['-strip', '-quality', '85', str(path)]


def write_json(path, workspace):
    def lines(name, items):
        return f' "{name}": [\n' + ',\n'.join('  ' + json.dumps(item, ensure_ascii=False) for item in items) + '\n ]'

    spaces = ',\n'.join(
        '  {"id": %s, "name": %s, "items": [\n' % (json.dumps(space['id']), json.dumps(space['name']))
        + ',\n'.join('   ' + json.dumps(item, ensure_ascii=False) for item in space['items']) + '\n  ]}'
        for space in workspace['spaces']
    )
    text = '{\n' + ',\n'.join([
        lines('members', workspace['members']), f' "spaces": [\n{spaces}\n ]',
        lines('tasks', workspace['tasks']), lines('notes', workspace['notes']),
    ]) + '\n}\n'
    path.write_text(text, encoding='utf-8')


def main():
    rng = random.Random(SEED)
    workspace = make_workspace(rng)
    write_json(HERE / 'rukun.json', workspace)

    commands = []
    for folder in ('photos', 'avatars'):
        shutil.rmtree(HERE / folder, ignore_errors=True)
        (HERE / folder).mkdir()
    # The commands come from one seeded generator in a fixed order, then run in parallel.
    for number in range(1, PHOTO_COUNT + 1):
        commands.append(image_command(rng, HERE / 'photos' / f'p{number:04d}.jpg', *PHOTO_PIXELS, rng.randint(1, 3)))
    for member in workspace['members']:
        commands.append(image_command(rng, HERE / 'avatars' / member['avatar'], AVATAR_PIXELS, AVATAR_PIXELS, 1))
    with ThreadPoolExecutor() as pool:
        list(pool.map(lambda command: subprocess.run(command, check=True), commands))

    spaces, tasks, notes = workspace['spaces'], workspace['tasks'], workspace['notes']
    items = [item for space in spaces for item in space['items']]
    assert len(tasks) == TASK_COUNT and len({task['id'] for task in tasks}) == TASK_COUNT
    assert len(notes) == NOTE_COUNT and len(spaces) == len(SPACES)
    assert len({item['id'] for item in items}) == len(items)
    task_ids, note_ids = {task['id'] for task in tasks}, {note['id'] for note in notes}
    assert all(item['task'] in task_ids for item in items if item['kind'] == 'task')
    assert all(item['note'] in note_ids for item in items if item['kind'] == 'note')
    photos = [item['photo'] for item in items if 'photo' in item]
    assert len(photos) == len(set(photos)) and all((HERE / 'photos' / photo).exists() for photo in photos)

    long_space = next(space for space in spaces if space['id'] == LONG_SPACE)
    print(f'{len(tasks)} tasks, {len(notes)} notes, {len(items)} items in {len(spaces)} spaces '
          f'({len(long_space["items"])} in #{LONG_SPACE}), {len(photos)} photos in messages')


if __name__ == '__main__':
    main()
