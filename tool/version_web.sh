#!/usr/bin/env bash
# Gives the web build's JS and fonts new file names for every deploy.
# The toolution.net zone forces a 4-hour browser cache on .js files, whatever
# web/_headers says, so phones kept the old app for hours. index.html is not
# cached (web/_headers), so new names in it reach phones on the next load.
# Usage: tool/version_web.sh <build/web dir> <version>
set -euo pipefail
dir=$1
v=$2
cd "$dir"
grep -q 'main\.dart\.js' flutter_bootstrap.js
grep -q 'src="flutter_bootstrap\.js"' index.html
mv main.dart.js "main.$v.dart.js"
sed -i "s/main\.dart\.js/main.$v.dart.js/g" flutter_bootstrap.js
mv flutter_bootstrap.js "flutter_bootstrap.$v.js"
sed -i "s/src=\"flutter_bootstrap\.js\"/src=\"flutter_bootstrap.$v.js\"/" index.html
grep -q "main.$v.dart.js" "flutter_bootstrap.$v.js"
grep -q "flutter_bootstrap.$v.js" index.html
# Fonts too: the zone caches .otf/.ttf for 4 hours, and the icon font is cut
# down to the icons the build uses, so an old copy shows new icons as blanks.
# FontManifest.json is not cached, so new names in it are fetched at once.
python3 - "$v" <<'PY'
import json, os, sys
v = sys.argv[1]
fm = json.load(open('assets/FontManifest.json'))
for fam in fm:
    for f in fam['fonts']:
        old = f['asset']
        base, ext = os.path.splitext(old)
        new = f'{base}.{v}{ext}'
        os.rename(os.path.join('assets', old), os.path.join('assets', new))
        f['asset'] = new
json.dump(fm, open('assets/FontManifest.json', 'w'), separators=(',', ':'))
PY
echo "web JS versioned as $v"
