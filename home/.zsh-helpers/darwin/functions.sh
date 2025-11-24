function showAllFiles() {
  defaults write com.apple.finder AppleShowAllFiles YES; killall Finder /System/Library/CoreServices/Finder.app
}

function hideFiles() {
  defaults write com.apple.finder AppleShowAllFiles NO; killall Finder /System/Library/CoreServices/Finder.app
}

function kill_dock() {
    killall -KILL Dock
}