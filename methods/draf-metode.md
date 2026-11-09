# Draf: perbaikan metode penelitian untuk AFL berikutnya

Draf ini memuat perbaikan atas AFL 1 dan keputusan yang diambil sesudahnya. Bagian yang
bertanda [isi] perlu dilengkapi sebelum dikumpulkan.

## 1. Catatan perubahan dari AFL 1

| Bagian | AFL 1 | Revisi | Alasan |
| --- | --- | --- | --- |
| Pembanding native | Rune | GPUI | Rune berumur kurang dari satu bulan, belum punya rilis, dan meminta aplikasi memakai revisi dev. GPUI sudah dipakai di aplikasi produksi, yaitu editor Zed. Rune tetap dibahas sebagai related work dan rujukan developer experience. Ringkasan rencana sudah memakai GPUI. |
| Judul | ... Perbandingan Performa dengan Tauri, Electron, dan Rune | ... Perbandingan Performa dengan Tauri, Electron, dan GPUI | Mengikuti pembanding baru. |
| Pertanyaan penelitian 1 | ... dibandingkan Tauri, Electron, dan Rune ... | ... dibandingkan Tauri, Electron, dan GPUI ... | Sama. |
| Aplikasi uji | Penjelajah perpustakaan musik dengan data sampel lokal | Rukun versi desktop: ruang kerja keluarga dengan ruang (space), tugas, dan catatan, dengan data sintetis | Rukun berangkat dari laporan Ideation mata kuliah Digital Entrepreneurship Product Development dan mengambil prinsip Slack, Linear, dan Obsidian, yang ketiganya aplikasi Electron. Jenis aplikasi ini lebih dikenal developer dan lebih mewakili aplikasi desktop berbasis web daripada pemutar musik. |
| Artifact | Framework minimal, cukup untuk aplikasi uji | Framework umum bernama thor. Penelitian mengukur satu versi yang dibekukan (research tag). | Framework dikembangkan untuk aplikasi nyata. Angka penelitian hanya berlaku untuk versi yang diukur. |
| Variabel | Disebut namanya | Didefinisikan secara operasional (bagian 5) | Agar setiap angka dapat diulang dan dibandingkan antar-framework. |
| Tahap B | Tanpa aturan AI, batas waktu, dan definisi selesai | Tanpa AI assistant, batas 60 menit, kartu tugas dengan acceptance checks | Agar waktu penyelesaian dapat dibandingkan antar-partisipan. |

## 2. Artifact: thor

thor adalah native UI framework berbasis Odin untuk macOS. Framework ini diekstrak dari OnlyMuse
dan terdiri atas beberapa lapisan: `platform` (jendela AppKit, event, input teks termasuk IME),
`render` (Metal), `font` (Core Text), `icon` (SF Symbols), `image` (decode dan cache tekstur),
`ui` (layout immediate mode), `kit` (komponen), `dev` (alat ukur), dan `app` (titik masuk).

Versi 0.1 selesai pada 9 November 2026. Ekstraksi ini tidak mengubah perilaku OnlyMuse. Hal itu
diperiksa dengan tiga cara: tangkapan layar enam halaman sebelum dan sesudah ekstraksi berbeda
kurang dari 10 piksel, sama dengan selisih antara dua kali pengambilan pada build lama;
benchmark frame tetap berada dalam sebaran antar-run; dan enam uji otomatis berjalan tanpa
jendela.

## 3. Siklus DSR

| Iterasi | Waktu | Build | Evaluate |
| --- | --- | --- | --- |
| 1 | Minggu 1 | Halaman Tasks dengan API mentah thor v0.1 | Jumlah baris kode dan daftar kendala |
| 2 | Minggu 1 | Perbaikan API (P0) dan komponen Tier 1, lalu seluruh aplikasi uji dibangun | Jumlah baris kode dan daftar kendala dibandingkan dengan iterasi 1 |
| Evaluasi akhir | Minggu 8–9 | Research tag | Tahap A dan tahap B |

Iterasi 1 sudah berjalan. Halaman Tasks pada v0.1 membutuhkan 256 baris kode, dan 15 kendala
tercatat, misalnya belum ada dokumentasi, virtual list, komponen gambar, dan checkbox, serta
input teks yang harus dihubungkan sendiri oleh aplikasi.

Iterasi 2 juga sudah berjalan. Setelah perbaikan API, halaman Tasks yang sama membutuhkan 127
baris kode, turun dari 256. Seluruh aplikasi uji (sidebar, halaman Tasks, halaman ruang, dan
halaman catatan) membutuhkan 446 baris. Delapan kendala tersisa, misalnya dokumentasi yang
belum ada dan container yang dapat diklik.

## 4. Versi yang dikunci dan perangkat

| Komponen | Versi |
| --- | --- |
| Odin | `dev-2026-10` (commit `84bc3fc21`), dikunci dari minggu 1 hingga tahap B selesai |
| thor | Research tag, dibuat setelah pilot pada minggu 7. Tidak ada perubahan, termasuk dokumentasi, hingga sesi tahap B terakhir. |
| Electron, Tauri, GPUI | Dikunci saat aplikasi masing-masing mulai dibangun: [isi versi Electron], [isi versi Tauri], [isi revisi GPUI] |
| Perangkat | MacBook Pro 14 inci (Mac16,1), Apple M4, RAM 16 GB, macOS 27.2 |

## 5. Tahap A: computational experiment

### Aplikasi uji

Aplikasi uji adalah potongan desktop dari Rukun, ruang kerja digital untuk keluarga yang
dirancang di laporan Ideation mata kuliah Digital Entrepreneurship Product Development. Satu
aplikasi yang sama dibangun dengan keempat framework, mengikuti satu spesifikasi tertulis
tentang ukuran, warna, dan font. Aplikasi ini berisi sidebar dengan 12 ruang keluarga, halaman
Tasks (5.000 tugas dengan pencarian dan virtual list), halaman ruang (timeline pesan, tugas,
daftar, dan catatan dengan tinggi yang berbeda-beda, sebagian dengan foto dan emoji), dan
halaman catatan (read-only, dengan checklist dan backlink). Fitur Today, kalender, suara, dan
AI tidak dibangun, karena fitur suara dan AI membutuhkan jaringan sehingga pengukuran tidak
dapat diulang dengan hasil yang sama.

Datanya sintetis, dibuat oleh generator dengan seed tetap: 5 anggota keluarga, 12 ruang dengan
9.740 item timeline (4.000 di antaranya di ruang `#keluarga`), 5.000 tugas selama tiga tahun,
200 catatan, 400 foto JPEG berukuran 480 × 360 piksel, dan 5 avatar. Tidak ada data pribadi,
percakapan nyata, atau karya berhak cipta. Data disertakan di dalam setiap aplikasi. Setiap
aplikasi dibuka pada halaman Tasks.

### Kondisi pengukuran

Satu Mac, terhubung ke listrik, Low Power Mode mati. Pengukuran memakai layar bawaan dengan
refresh rate 60 Hz, dan monitor eksternal dilepas. Satu aplikasi berjalan pada satu waktu,
dengan ukuran jendela yang sama (1.100 × 720 point). Safari dan aplikasi lain berbasis WebKit
ditutup.

### Definisi operasional variabel

| Variabel | Definisi | Alat ukur |
| --- | --- | --- |
| Startup time (ms) | Waktu dari harness menjalankan executable di dalam `.app` hingga baris `first-frame` diterima dari stdout aplikasi. Baris ini dicetak setelah frame pertama yang menampilkan daftar tugas. Diukur sebagai warm start. | Skrip harness |
| Frame time p50 dan p99 (ms) | Selang antara awal dua frame berurutan selama aplikasi menggulir dirinya sendiri dengan kecepatan 1.500 point per detik selama 20 detik. Waktu diambil di callback yang digerakkan layar: display link pada thor, `requestAnimationFrame` pada Electron dan Tauri, dan frame callback pada GPUI. | Log aplikasi, diolah oleh harness |
| Memory usage (MB) | Physical footprint, dijumlahkan dari semua proses milik aplikasi: main, renderer, GPU, dan utility pada Electron, serta proses aplikasi dan layanan XPC WebKit (WebContent, Networking, GPU) pada Tauri. Dilaporkan rata-rata dan puncaknya selama skenario. | `footprint` atau `vmmap` [isi] |
| Idle CPU usage (%) | Total CPU time semua proses milik aplikasi selama 60 detik tanpa input, dibagi 60 detik, dalam persen satu core. | `ps` atau `top` [isi] |
| Bundle size (MB) | Ukuran `.app` hasil release build. | `du` |
| Clean build time (detik) | Dari source hingga `.app` release, setelah semua dependensi diunduh dan semua cache serta output build dihapus. | `hyperfine` |
| Incremental build time (detik) | Dari menyimpan perubahan satu label hingga label baru tampil, dengan siklus pengembangan bawaan tiap framework: hot reload Vite pada Electron dan Tauri, build ulang dan jalankan ulang pada GPUI dan thor. | Stopwatch dari rekaman layar |
| Lines of code (baris) | Baris kode aplikasi uji yang ditulis peneliti, tanpa kode framework, file yang dihasilkan otomatis, dan aset. | `tokei` |
| Setup time (menit) | Waktu dari mesin virtual macOS yang bersih hingga aplikasi uji berjalan, mengikuti panduan getting started resmi tiap framework. Waktu unduh dan instalasi termasuk. Setiap langkah dicatat. | Stopwatch dan catatan langkah |

### Skenario

| Skenario | Variabel | Cara |
| --- | --- | --- |
| Setup | Setup time | Satu mesin virtual macOS bersih per framework (misalnya Tart). |
| S1 start | Startup time | Harness menjalankan aplikasi, menunggu baris `first-frame`, lalu menutupnya. 10 run setelah 1 run yang dibuang. |
| S2 gulir tugas | Frame time, CPU, memory | Aplikasi menggulir daftar tugas sendiri dengan kecepatan dan durasi tetap. Semua baris setinggi sama. |
| S3 gulir timeline | Frame time, memory puncak | Sama, pada timeline `#keluarga`: item dengan tinggi berbeda, teks yang membungkus, emoji, dan 232 foto yang ikut di-decode. |
| S4 idle | Idle CPU | 60 detik tanpa input, setelah S1. |
| Build | Clean dan incremental build time | Seperti definisi di atas. |
| Ukuran dan kode | Bundle size, lines of code | Seperti definisi di atas. |

Setiap skenario diulang 10 kali.

### Analisis

Untuk setiap skenario dan framework: rata-rata, simpangan baku, median, dan sebaran. Normalitas
diuji dengan Shapiro–Wilk. Data normal diuji dengan ANOVA satu arah, atau Welch ANOVA bila
variansnya tidak sama. Data yang tidak normal diuji dengan Kruskal–Wallis, dilanjutkan uji
Dunn dengan koreksi Holm.

### Menjaga keadilan perbandingan

Peneliti merancang thor dan membangun keempat aplikasi, sehingga keahliannya tidak setara antar-
framework. Untuk menguranginya, setiap pembanding dibangun dari template resminya dan mengikuti
panduan performanya sendiri, termasuk virtual list: TanStack Virtual pada Electron dan Tauri,
dan `uniform_list` pada GPUI. Electron dan Tauri memakai satu frontend React yang sama, sehingga
perbedaan keduanya hanya pada shell. Keempat aplikasi, skrip harness, dan data mentah
dipublikasikan.

## 6. Tahap B: developer evaluation

- Partisipan: kriteria AFL 1 tetap berlaku. Pengalaman memakai Odin dan immediate mode UI
  dicatat, tetapi tidak disyaratkan.
- Perangkat: satu Mac yang sama untuk setiap sesi, dengan Odin dan thor sudah terpasang.
  Setup diukur di tahap A, bukan bagian tugas.
- Starter project: aplikasi uji dengan data dan sidebar. Halaman Tasks masih kosong.
- Kartu tugas: membangun halaman Tasks, yaitu daftar tugas yang dapat dicari dan digulir.
  Acceptance checks: setiap tugas dapat dicapai dengan menggulir, pencarian menyaring
  berdasarkan judul dan nama penanggung jawab, dan klik memilih satu baris.
- Bahan: cheatsheet, halaman getting started, dan contoh kode, ditambah gallery komponen bila
  research tag memilikinya. Tidak ada AI assistant.
- Waktu: paling lama 60 menit, dengan rekaman layar. Task completion time dihitung dari awal
  tugas hingga partisipan menyatakan selesai. Partisipan yang kehabisan waktu dicatat 60 menit,
  beserta checks yang gagal.
- Error: jumlah build yang gagal, ditambah acceptance checks yang gagal saat partisipan
  menyatakan selesai.
- SUS: memakai adaptasi bahasa Indonesia (Sharfina dan Santoso, 2016) bila partisipan menjawab
  dalam bahasa Indonesia. Skor setiap partisipan, rata-rata, dan sebarannya dilaporkan dan
  dibandingkan dengan acuan 68 (Sauro dan Lewis, 2016). Dengan 8 partisipan, hasil ini bersifat
  formatif, bukan uji beda.
- Wawancara: semi-terstruktur dan singkat, lalu dianalisis secara tematik (Braun dan Clarke,
  2006).
- Pilot: satu atau dua orang pada build kandidat. Dokumentasi dan cacat diperbaiki, research
  tag dibuat, lalu 8 sesi berjalan.

## 7. Keterbatasan (revisi)

- Penelitian dibatasi pada macOS.
- Angka performa berlaku untuk research tag dan komponen yang dipakai aplikasi uji. Versi
  berikutnya menambah pekerjaan di setiap frame (focus, overlay, banyak jendela), sehingga
  perlu diukur ulang.
- Frame time adalah frame yang dimulai aplikasi, bukan frame yang ditampilkan compositor.
  Tidak ada aplikasi yang dapat melihat kapan compositor menampilkan frame-nya.
- Peneliti merancang thor dan membangun keempat aplikasi.
- Tahap B tidak memakai AI assistant, sehingga waktu tugas dapat lebih lama daripada praktik
  developer pada 2026.
- Jumlah partisipan kecil, sehingga temuan kualitatif tidak dapat digeneralisasi.
- Hanya satu jenis aplikasi uji, yaitu potongan Rukun, dan Rukun sendiri dirancang sebagai aplikasi
  mobile dan web. Cold start tidak diukur karena membutuhkan reboot setiap run.

## 8. Jadwal

Minggu dihitung dari Senin, 9 November 2026.

| Minggu | Tanggal | Framework | Penelitian |
| --- | --- | --- | --- |
| 1 | 9–15 Nov | Odin dikunci. thor v0.1. Iterasi 1. | Perbaikan metode. Spesifikasi aplikasi uji. Generator data. |
| 2 | 16–22 Nov | Perbaikan API P0 (1, 2, 4, 5). | Frontend React untuk Electron dan Tauri. Kunci versinya. |
| 3 | 23–29 Nov | Komponen Tier 1, alat ukur, bundle. | Frontend React. |
| 4 | 30 Nov–6 Des | Aplikasi uji lengkap di thor. Iterasi 2. | Aplikasi GPUI. Kunci revisinya. |
| 5 | 7–13 Des | Cadangan. | Aplikasi GPUI. Skrip harness. |
| 6 | 14–20 Des | Cadangan. | Tangkapan layar keempat aplikasi berdampingan. |
| 7 | 21–27 Des | Dokumentasi. Pilot sebelum 23 Desember. Research tag. | Uji coba harness. |
| 8 | 28 Des–3 Jan | | Tahap A. |
| 9 | 4–10 Jan | | Tahap B. Analisis dimulai. |

## Rujukan baru

- Braun, V., dan Clarke, V. (2006). Using thematic analysis in psychology. *Qualitative
  Research in Psychology*, 3(2), 77–101.
- Brooke, J. (1996). SUS: A "quick and dirty" usability scale. Dalam *Usability Evaluation in
  Industry*. Taylor & Francis.
- Hevner, A. R., March, S. T., Park, J., dan Ram, S. (2004). Design science in information
  systems research. *MIS Quarterly*, 28(1), 75–105.
- Sauro, J., dan Lewis, J. R. (2016). *Quantifying the User Experience* (edisi ke-2). Morgan
  Kaufmann.
- Sharfina, Z., dan Santoso, H. B. (2016). An Indonesian adaptation of the System Usability
  Scale (SUS). *2016 International Conference on Advanced Computer Science and Information
  Systems (ICACSIS)*, 145–148.
