# Year in Pages

**Your reading year, recapped, right on your e-reader.** A KOReader plugin that turns your reading statistics into a year-end recap you page through like a book: hours read, books finished, your longest streak, your biggest month and what kind of reader you are.

No account, no server, no sync. Everything is built on the device from KOReader's own Reading statistics.

> **Beta: looking for testers.** The stats and layout code is tested off-device, but the plugin hasn't been run on a Kindle or Kobo yet. If you try it, please [open an issue](../../issues) with your device and whether it worked.

[![Buy me a coffee](https://img.shields.io/badge/Support-Buy%20me%20a%20coffee-ffdd00?style=for-the-badge&logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/mehmeteminf)

## What's in your recap

1. **Time well spent:** total hours read, how many days you read, and how it compares with last year
2. **Page after page:** pages read across all your books
3. **Finished:** every book you read to the end, with the date
4. **Your top books:** the five books you spent the most time with
5. **Month by month:** a bar chart of your reading year
6. **Reader type:** Early Bird, Afternoon Reader, Evening Reader or Night Owl, plus your favourite day and busiest hour
7. **On a roll:** your longest daily streak and your biggest single day

The recap is saved as `Year in Pages 2026.html` in a "Year in Pages" folder in your home folder. Copy it to a phone or computer and it opens in any browser, so it's easy to share.

## Install

1. Download `yearinpages.koplugin.zip` from the [latest release](../../releases/latest) and unzip it.
2. Copy the `yearinpages.koplugin` folder into KOReader's `plugins` folder:
   - Kindle: `koreader/plugins/`
   - Kobo: `.adds/koreader/plugins/`
   - Android: `koreader/plugins/` in app storage
3. Restart KOReader.

## Use

Top menu, **Tools** tab, **Year in Pages (reading recap)**. Pick a year and your recap opens.

Reading statistics must be on (Tools, Reading statistics). It is on by default in KOReader. The recap only knows what the statistics recorded, so the earlier you turned them on, the fuller your year.

## How "finished" is counted

A book counts as finished in a year when you read its last page that year *and* spent at least 10 minutes in it that year. That way a book you only opened at the end doesn't count.

## Development

The stats and layout code is plain Lua with no KOReader dependencies, tested off-device with [fengari](https://fengari.io) against a SQLite database built with KOReader's statistics schema:

```bash
cd tests
npm install
npm test
```

`npm test` also writes a sample recap to `tests/out/sample-2026.html`.

To build the release zip on Windows: `powershell -File scripts/pack.ps1`.

## Support

Year in Pages is free and always will be. If it made you smile, you can [buy me a coffee](https://buymeacoffee.com/mehmeteminf). Bug reports and ideas are welcome in [Issues](../../issues).

## License

MIT
