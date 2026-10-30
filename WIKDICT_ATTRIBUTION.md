# WikDict data attribution

The German–English and English–German translation data in
`Resources/dictionary.sqlite` comes from [WikDict](https://www.wikdict.com/page/download)
by Karl Bartel. WikDict derives its data from Wiktionary via DBnary. The source
archives are [wikdict-de-en.zip](https://download.wikdict.com/dictionaries/stardict/wikdict-de-en.zip)
and [wikdict-en-de.zip](https://download.wikdict.com/dictionaries/stardict/wikdict-en-de.zip).

This app transforms those StarDict archives into a SQLite index, extracts
translation equivalents, and combines them with Openjam English–Persian data
to create German–Persian entries via English. The transformed WikDict data and
German–Persian derivative entries are distributed under
[Creative Commons Attribution-ShareAlike 4.0 International](https://creativecommons.org/licenses/by-sa/4.0/).
WikDict, Wiktionary, DBnary, and their contributors do not endorse Rava.
