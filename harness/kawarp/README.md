# Fluid artwork settings harness

The redesign's Now playing page (`Redesigned/NowPlayingBar/NowPlayingBarSettings.m`) and the Fluid artwork page
it opens (`Redesigned/Player/PlayerBackgroundSettings.m`), on the real `Settings/` framework, with the preview
drawn by the Kit's renderer (`Redesigned/Kit/SGRWarp.m`). The player's side is `harness/player`'s `fluid`
scenario.

    ./build.sh
    xcrun simctl install <udid> build/KawarpHarness.app
    SIMCTL_CHILD_HARNESS_COVER=<picture> xcrun simctl launch <udid> com.vojta.kawarpharness dump select=1.1 slide=0.2:3 dump

Launch it on an iOS 26 simulator by UDID; the iOS 27 runtime kills an app that has a scene manifest but no
scene delegate. `main.m` lists the setup words (`old-off` stores the Moving background switch off, to see it
read as Still artwork) and the actions, one every 1.2 s from 1 s in. Without `HARNESS_COVER` nothing is
playing and the preview warps its generated sample; keep real covers out of the repo.
