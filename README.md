# Tang Nano 1Kで鳴らすKansas City Standard風FSK

Gowin Tang Nano 1Kの27 MHzクロックから、初期マイクロコンピューターのカセット保存で使われたKansas City Standard（KCS）風のFSK音を生成するサンプルです。

モデムのような音を、まずは安価なパッシブ圧電ブザーで聴けるようにしています。実際のカセットデータロガーを実装することが目的ではなく、音の中にシリアルビットが埋め込まれる仕組みをFPGAで観察するための小さな教材です。

## できること

- Aボタン：4秒のレベル調整音から開始し、`ABCDEFGHIJKLMNOPQRSTUVWXYZ`を先頭から反復送信
- Bボタン：停止
- 再生中：オンボードRGB LEDの緑色LEDがレベル調整中またはmark（論理1）に連動
- 送信出力：P2ヘッダのFPGA pin 35（LCD_R0兼用）

電源投入直後は停止しています。Aボタンを押すと4秒間の1200 Hz音を出してから、AからZを繰り返します。

## 信号仕様

| 項目 | このサンプルの設定 |
| --- | --- |
| FPGA | Gowin `GW1NZ-LV1QN48C6/I5` |
| システムクロック | 27 MHz（FPGA pin 47） |
| ビットレート | 300 baud |
| mark / 論理1 | 2400 Hzを8周期／ビット |
| space / 論理0 | 1200 Hzを4周期／ビット |
| フレーム | start `0` + 8-bit ASCII LSB-first + stop `1`×2 |
| 文字列 | `ABCDEFGHIJKLMNOPQRSTUVWXYZ`を反復 |
| レベル調整 | A開始時に1200 Hzを4秒 |

1ビットは約3.333 msです。1文字は11ビットなので、1文字あたり約36.7 ms、理想的なペイロード速度は約27文字/秒です。

たとえば`A`はASCII `0x41`で、データ部をLSBから読むと次のようになります。

```text
data:  1 0 0 0 0 0 1 0
frame: 0 | 1 0 0 0 0 0 1 0 | 1 1
       start       ASCII A       stop
```

### ボードのピン

| 信号 | FPGA pin | Tang Nano 1Kでの役割 |
| --- | ---: | --- |
| `clk_27m` | 47 | 27 MHz入力 |
| `buzzer` | 35 | P2ヘッダ、LCD_R0兼用 |
| `key_a_n` | 13 | Aボタン、active-low |
| `key_b_n` | 44 | Bボタン、active-low |
| `led_g_n` | 11 | オンボードRGB LED緑、active-low |

## ブザーの接続

### パッシブ圧電ブザー

今回のように圧電ブザーを使う場合は、外部5 Vを使わず、P2 pin 35から1 kΩを直列に入れます。

```text
Tang Nano P2 pin35 ─ 1 kΩ ─ 圧電ブザー＋
Tang Nano GND      ───────── 圧電ブザー−
```

圧電ブザーをFPGA GPIOへ完全直結せず、直列抵抗を入れてください。ブザーに極性表示がない場合は、2端子を入れ替えても通常は壊れません。

### ダイナミックスピーカー／電磁ブザー

8 Ωや25 Ωのダイナミックスピーカーは、FPGA pin 35やTang Nano本体の5 Vピンへ直接接続しないでください。外部電源とMOSFET、またはオーディオアンプを使います。

2SK4150を使うローサイドスイッチの例です。

```text
外部電源＋3.3 V ─ 電流制限抵抗 ─ スピーカー＋
スピーカー− ─ Drain (D)
Source (S) ─ 外部電源GND ─ Tang Nano GND
Gate (G) ─ 1 kΩ ─ Tang Nano P2 pin35
Gate (G) ─ 100 kΩ ─ GND
```

2SK4150は印字面を手前、足を下にしたとき左から`S-D-G`です。外部電源を使ってもGNDはTang Nanoと共通にします。5 Vを使う場合は必ず電流を制限し、まずは外部3.3 Vで試してください。電磁ブザーやリレーのようなコイル負荷には、負荷に合わせたフライバックダイオードも必要です。

## KCSとは何か

Kansas City Standard（KCS）は、1975年11月7〜8日にBYTE誌がミズーリ州Kansas Cityで開いたオーディオカセット標準化シンポジウムを起源とする、初期マイクロコンピューター向けのデータ保存方式です。当時の安価な民生カセットレコーダーを、フロッピーディスクの代わりの記録媒体として使うことが狙いでした。

仕組みはシンプルなAFSKです。論理0と論理1を異なる音の周波数に割り当て、音声入出力をシリアル回線のように扱います。このため、昔のカセットインターフェースは「音を使うモデム」によく似ています。ただし電話回線用モデムそのものではなく、テープの速度変動や録音レベルに耐えるための低速なローカル記録方式です。

KCSの面白いところは、名前は大げさなのに中身はかなり実用的なことです。2400 Hzを8周期、1200 Hzを4周期にすると、どちらも1ビットが約3.33 msになり、1と0の波形を単純なカウンターで作れます。一方で、元の暫定仕様は先頭のmark時間やデータブロックの扱いまで含んでおり、単に周波数を2種類出せば完全互換になるわけではありません。

この実装の4秒1200 Hzレベル調整音は、録音レベルを合わせやすくするための独自の前置きです。元資料で説明されたmarkプリアンブルとは異なるため、本プロジェクトは「KCSの音形を使った教育用送信機」と位置づけています。受信機との完全互換を狙う場合は、プリアンブル、ブロック、パリティ、停止条件を受信側の仕様に合わせてください。

## カンザスシティの蘊蓄

KCSのKansas Cityは、カンザス州の都市名ではなく、ミズーリ州側のKansas Cityです。ミズーリ州務長官の年表によれば、現在のKansas CityにつながるTown of Kansasは1850年に法人化されました。川と西部交易、鉄道によって発展した都市で、会議名がそのままデータ方式の通称になりました。

技術史以外では、Kansas Cityは次の三つの顔でも知られます。

- 1920〜30年代に12th & Vineや18th & Vine周辺で発展したジャズ
- 1920年代にHenry Perryから広がったKansas City-style barbecue
- 馬や犬のための水場から始まり、現在の「City of Fountains」につながった噴水文化

つまりこのプロジェクトは、カセットの音を作りながら、ジャズとバーベキューと噴水の街の名前を鳴らしています。なお、Kansas Cityの歴史には先住民、奴隷制、ミズーリ・カンザス境界紛争、隔離政策と公民権の歴史も含まれます。食と音楽だけに単純化しないことも、都市の蘊蓄を扱うときの大事な前提です。

## サッポロシティの蘊蓄

札幌はKCSの規格名ではありません。このREADMEでは、Kansas Cityという技術史上の地名と対になる、もう一つの都市雑学として札幌を扱います。

札幌市の資料によると、1869年に開拓使が設置され、札幌が北海道開拓の中心として整備されました。1871年には大通と創成川を軸にした碁盤の目の市街区画が形づくられ、現在の札幌らしい都市構造の骨格になっています。1876年には札幌農学校が開校し、ウィリアム・クラークが教頭として招かれました。

地名「札幌」の語源は一つに決着していません。札幌市は、アイヌ語の「サッ・ポロ・ペッ」（乾いた大きな川）説と、「サリ・ポロ・ペッ」（葦原が広い川）説などを紹介しています。名前の由来自体が、川と土地の見え方の違いを残す小さな歴史資料になっています。

札幌市制は1922年に施行され、1950年には第1回さっぽろ雪まつりが開かれました。Kansas Cityが川・鉄道・カセット会議の街なら、札幌は川・計画都市・雪の街です。どちらも、土地の性格が後の文化や技術のイメージに長く残っている点が面白いところです。

## Gowin IDEでのビルド

1. 新規プロジェクトを作成し、デバイスに`GW1NZ-LV1QN48C6/I5`を選択。
2. `src/fsk_buzzer.v`をトップソースとして追加。
3. `src/tang1k.cst`をPhysical Constraints Fileとして追加。
4. Top moduleを`fsk_buzzer`に設定し、Synthesize、Place & Route、Programを実行。

生成された`.fs`をopenFPGALoaderで一時転送する例です。

```sh
openFPGALoader --detect --cable ft2232
openFPGALoader --write-sram --reset --cable ft2232 path/to/tang1k_fsk.fs
```

電源断後も残す場合は、動作確認後にFlashへ書き込みます。

```sh
openFPGALoader --write-flash --verify --cable ft2232 path/to/tang1k_fsk.fs
```

FTDIデバイスが複数ある場合は、`--ftdi-serial 'デバイスのシリアル名'`を追加してください。Tang Nano 1KのJTAG IDCODEは`0x0100681B`、Gowinの`GW1NZ-1`として検出されます。

## ファイル

- `src/fsk_buzzer.v` — KCS風FSK、A/Bボタン、デバウンス、LED表示
- `src/tang1k.cst` — Tang Nano 1Kのクロック、ボタン、LED、ブザー出力の制約

## 参考資料

- [BYTE Magazine, February 1976: Audio Cassette Standards Symposium](https://vintageapple.org/byte/pdf/197602_Byte_Magazine_Vol_00-06_Color_Graphics.pdf) — KCSの原資料に近い会議報告と暫定仕様
- [Kansas City standard](https://en.wikipedia.org/wiki/Kansas_City_standard) — KCS、CUTS、初期マイコンでの利用の概説
- [Missouri Secretary of State: Timeline of Historic Missouri](https://www.sos.mo.gov/default.aspx?PageID=10066) — Town of Kansasの1850年法人化
- [Visit KC: Kansas City traditions](https://www.visitkc.com/articles/everything-you-need-know-about-kansas-city-traditions/) — ジャズ、バーベキュー、噴水の背景
- [札幌市: 札幌の冬の歴史](https://www.city.sapporo.jp/kensetsu/yuki/library/hist/01.html) — 開拓使、碁盤の目の市街区画、外国人技術者
- [札幌市: まちづくり戦略ビジョン教材](https://www.city.sapporo.jp/ncms/vision2-kyouzai/) — 札幌農学校、クラーク、市制などの年表
- [札幌市: 都市計画の豆知識](https://www.city.sapporo.jp/keikaku/machibon/machibon6/mamechisiki.html) — 「札幌」の地名由来の複数説

## 注意

これは教育・実験用サンプルです。圧電ブザーとダイナミックスピーカーでは必要な駆動回路が異なります。FPGA GPIOに外部電源や低インピーダンスのスピーカーを接続せず、電源電圧、電流、GND、MOSFETのピン配置を確認してから通電してください。
