"""Switches the generated Android project from debug to release signing."""
import os
import re
import sys

path = 'android/app/build.gradle'
if not os.path.exists(path):
    sys.exit('build.gradle not found (Kotlin DSL template?). Pin Flutter 3.27.4.')
s = open(path, encoding='utf-8').read()
block = '''    signingConfigs {
        release {
            def props = new Properties()
            def kf = rootProject.file("key.properties")
            if (kf.exists()) { props.load(new FileInputStream(kf)) }
            keyAlias props["keyAlias"]
            keyPassword props["keyPassword"]
            storeFile file(props["storeFile"])
            storePassword props["storePassword"]
        }
    }

'''
assert '    buildTypes {' in s, 'buildTypes block not found'
s = s.replace('    buildTypes {', block + '    buildTypes {', 1)
s, n = re.subn(r'signingConfig\s*=?\s*signingConfigs\.debug',
               'signingConfig = signingConfigs.release', s)
assert n == 1, 'debug signingConfig line not found'
open(path, 'w', encoding='utf-8').write(s)
print('Release signing configured')
