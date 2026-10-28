#!/bin/sh
# Qt 6.12 added a QML type named Color (QtQuick/Color 6.12). Omarchy's shell has
# its own Color singleton and imports QtQuick unversioned, so Qt's type shadows
# it: every theme lookup is undefined and the bar, menu and notifications draw
# empty. Capping the import at 6.11 keeps Qt's Color out. Idempotent; the
# pacman hook zz-omarchy-vmpal-qtquick.hook runs it again after Omarchy updates.
grep -rlE "^import QtQuick\s*$" /usr/share/omarchy/shell --include=*.qml |
  xargs -r sed -i -E "s/^import QtQuick\s*$/import QtQuick 6.11/"
