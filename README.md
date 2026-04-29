<div align="center">

# Hoshi Reader

![Language](https://img.shields.io/github/languages/top/Manhhao/Hoshi-Reader)
![Platform](https://img.shields.io/badge/platform-iOS-lightgrey)
![License](https://img.shields.io/github/license/Manhhao/Hoshi-Reader)

Hoshi Reader is a lightweight Japanese EPUB reader with Yomitan dictionary support, made for immersion learning.
<p align="center">
    <img src="Pictures/books.PNG" width="25%" alt="books">
    <img src="Pictures/reader.PNG" width="25%" alt="reader">
    <img src="Pictures/popup_dict.PNG" width="25%" alt="popup">
    <img src="Pictures/appearance.PNG" width="25%" alt="appearance">
    <img src="Pictures/anki_view.PNG" width="25%" alt="anki">
    <img src="Pictures/dictionary_view.PNG" width="25%" alt="dictionary">
</p>

## Download
[![App Store](https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg)](https://apps.apple.com/app/hoshi-reader/id6758244332)

If you'd like to try out features early consider joining the TestFlight Beta

[![TestFlight](https://img.shields.io/badge/TestFlight-Join%20Beta-blue?logo=testflight&style=for-the-badge)](https://testflight.apple.com/join/G6KHqNAC)
## Features

<div align="left">

- **Vertical** (縦書き) and horizontal (横書き) text
- Yomitan-like pop-up dictionary with **deinflection support**
- Support for **all** Yomitan term, frequency and pitch dictionaries
- **Audio support** for Yomitan online and **local audio** sources made for Ankiconnect Android
- **AnkiMobile integration** with one-click mining
- Support for all core handlebars used by [Lapis](https://github.com/donkuri/lapis)
- **ッツ Reader sync**
- **Reading statistics**
- Dictionary search
- Bookshelves
- Custom themes, fonts and css

</div>
</div>

## Development

1. Clone the repository.
2. Open `HoshiReader.xcodeproj` in Xcode.

## Contributing

If you're planning on contributing a feature or significant change, please open an issue or message me on Discord first. I can't guarantee I'll accept every PR or feature, as I try to keep the project aligned with my own ideas.

## Libraries

| Name | License |
| :--- | :--- |
| [hoshidicts](https://github.com/Manhhao/hoshidicts) | GPLv3 |
| [EPUBKit](https://github.com/witekbobrowski/EPUBKit) | MIT |
| [SwiftUI Introspect](https://github.com/siteline/swiftui-introspect) | MIT |

## Attribution

| Name | Description | License |
| :--- | :--- | :--- |
| [Ankiconnect Android](https://github.com/KamWithK/AnkiconnectAndroid) | Local Audio implementation | GPLv3 |
| [Yomitan](https://github.com/yomidevs/yomitan) | Various code from pop-up dictionary | GPLv3 |
| [ッツ Ebook Reader](https://github.com/ttu-ttu/ebook-reader) | Statistics | BSD-3 |
| [JMdict for Yomitan](https://github.com/yomidevs/jmdict-yomitan) | Recommended term dictionary | CC-BY-SA-4.0 |
| [Jiten](https://github.com/Sirush/Jiten) | Recommended frequency dictionary | Apache-2.0 |
| [Kanji alive](https://github.com/kanjialive/kanji-data-media) | Default audio source | CC-BY-4.0 |
| [Tofugu/WaniKani Audio](https://github.com/tofugu/japanese-vocabulary-pronunciation-audio) | Default audio source | CC-BY-SA-4.0 |

## Issues

Please open an issue [here](https://github.com/Manhhao/Hoshi-Reader/issues) or in the TMW thread.

## Special Thanks

* **[TheMoeWay](https://learnjapanese.moe/)** - Enabling me to start learning real Japanese through immersion.
* **[Yomitan](https://github.com/yomidevs/yomitan)** - For serving as an invaluable tool and the primary inspiration for the pop-up dictionary.
* **[Ankiconnect Android](https://github.com/KamWithK/AnkiconnectAndroid)** - For providing a great mining experience on Android, which this project aims to replicate.
* **[ッツ Ebook Reader](https://github.com/ttu-ttu/ebook-reader)** - Inspiring the core reading experience.
* **[星街すいせい (Hoshimachi Suisei)](https://www.youtube.com/@HoshimachiSuisei)** - For being my motivation behind learning Japanese and giving the project a name (星読み).

## License

Distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for more information.
