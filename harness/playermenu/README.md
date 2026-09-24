# Player menu harness

The redesign's player menu (`Redesigned/Player/PlayerMenu.x`, drawn by `SGRPlayerMenu.m`) run for real over
a mock of Spotify's context menu sheet: a player with its ⋯ (`id=Context menu`), and the sheet presented from
it the way 9.1.78 nests it, whose rows are controls carrying the item's number as their accessibility
identifier. Share (9) pushes a page onto the sheet, Lyrics (28) turns itself on in place, every other row
dismisses the sheet. Speed and pitch are stubs that log.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/PlayerMenuHarness.app
    xcrun simctl launch --console-pty <udid> com.vojta.playermenuharness [hold|more|speed|tile|share|lyrics|outside|pending] [loading|stuck] [dump]

Every run taps the ⋯ at 1 s and reports the card, its rows top to bottom and whether Spotify's sheet is out
of sight at 2.2 s; the scenario then taps something on the card at 3 s and reports again. `loading` hands
the sheet its rows 1.5 s after it is up, `stuck` never does, `pending` (with `loading`) taps Add to playlist
on the last run's rows before Spotify's are in (the sheet is shown after 4 s), `dump` logs the
presentation's container.
