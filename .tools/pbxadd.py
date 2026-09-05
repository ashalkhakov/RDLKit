#!/usr/bin/env python3
"""Register source/header/resource files in RDLKit.xcodeproj/project.pbxproj.

The project uses classic explicit registration (objectVersion 56, no
PBXFileSystemSynchronizedRootGroup), so every added file needs a
PBXFileReference, a PBXBuildFile, a group `children` entry and a build-phase
`files` entry. Doing that by hand for a multi-file refactor is error-prone;
this does it idempotently.

    python3 .tools/pbxadd.py RDLKit RDLDocument.h RDLDocument.m ...
    python3 .tools/pbxadd.py RDLDesigner RDLCanvasRenderer.h RDLCanvasRenderer.m
    python3 .tools/pbxadd.py RDLDesigner --resource RDLWelcomeWindow.xib
    python3 .tools/pbxadd.py RDLDesignerTests --shared-ref RDLTablixEditor.xib

--shared-ref reuses the PBXFileReference another target already has for that
basename, instead of adding one to this target's group. Use it when a file that
lives in one target's directory has to be built into a second target as well:
a new reference would be resolved against the second group's own path and the
build would fail on a file that is not there.
"""
import hashlib, os, re, sys

PROJ = 'RDLKit.xcodeproj/project.pbxproj'

TARGETS = {
    # name: (group, sources phase, headers phase or None, resources phase or None)
    'RDLKit': ('45316B45CB436116EC434408', 'BBD96B25C463E4F2194995B6',
                '7904DBFDD0ABC4FECE1D6E19', None),
    'RDLDesigner':    ('367BDD79C0EB7824B717F2C6', '9A62AC01A2B00BE761FA3E90',
                None, 'F0BE7C60351F60A2424990B8'),
    # The checks drive the tablix panel, so its XIB has to be in the test
    # bundle as well: -bundleForClass: resolves there, not to RDLDesigner.app.
    'RDLDesignerTests': ('9D4444B8635515926096826D', 'A38464B071A1A354E92781FB',
                          None, '0C7A1FD3B4E5A6C7D8E9F001'),
}

FILETYPE = {
    '.h': 'sourcecode.c.h', '.m': 'sourcecode.c.objc',
    '.xib': 'file.xib', '.plist': 'text.plist.xml',
}


def uid(seed):
    """Stable 24-hex id, so re-running does not churn the file."""
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def insert_into_list(s, section_id, label, entry):
    """Append `entry` to the files=/children=( ... ) list of a given object.

    The list may be empty -- a target that has never had a resource is written
    by Xcode as `files = (\\n\\t\\t\\t);` -- so the body is matched as zero or
    more whole entry lines rather than as arbitrary text, which would otherwise
    run past the end of this object and into the next one.
    """
    m = re.search(r'(\t\t%s /\* [^*]*\*/ = \{\n(?:[^\n]*\n)*?\t\t\t%s = \(\n)'
                  r'((?:\t\t\t\t[^\n]*\n)*)(\t\t\t\);)'
                  % (section_id, label), s)
    if not m:
        raise SystemExit('could not find %s list of %s' % (label, section_id))
    body = m.group(2)
    if entry.strip() in body:
        return s, False
    new = m.group(1) + body + entry + '\n' + m.group(3)
    return s[:m.start()] + new + s[m.end():], True


def main():
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    target, args = args[0], args[1:]
    as_resource = '--resource' in args
    shared_ref = '--shared-ref' in args
    files = [a for a in args if not a.startswith('--')]
    if target not in TARGETS:
        raise SystemExit('unknown target %r; known: %s' % (target, ', '.join(TARGETS)))
    group, src_phase, hdr_phase, res_phase = TARGETS[target]

    s = open(PROJ).read()
    added = []
    for path in files:
        base = os.path.basename(path)
        ext = os.path.splitext(base)[1]
        ftype = FILETYPE.get(ext)
        if not ftype:
            raise SystemExit('unhandled extension %r' % ext)

        fref = uid('fileRef:%s:%s' % (target, base))
        bfile = uid('buildFile:%s:%s' % (target, base))

        if shared_ref:
            m = re.search(r'\t\t([0-9A-F]{24}) /\* %s \*/ = \{isa = PBXFileReference;'
                          % re.escape(base), s)
            if not m:
                raise SystemExit('no existing file reference for %r to share' % base)
            fref = m.group(1)

        # 1. PBXFileReference
        if not shared_ref and ('%s /* %s */' % (fref, base)) not in s:
            anchor = '/* End PBXFileReference section */'
            line = ('\t\t%s /* %s */ = {isa = PBXFileReference; '
                    'lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };\n'
                    % (fref, base, ftype, base))
            s = s.replace(anchor, line + anchor, 1)

        # 2. PBXBuildFile — headers of a framework target are Public
        if ext == '.h' and hdr_phase:
            phase, kind, settings = hdr_phase, 'Headers', ' settings = {ATTRIBUTES = (Public, ); };'
        elif as_resource or ext == '.xib':
            phase, kind, settings = res_phase, 'Resources', ''
        elif ext == '.m':
            phase, kind, settings = src_phase, 'Sources', ''
        else:
            phase = None
        if phase:
            if ('%s /* %s in %s */' % (bfile, base, kind)) not in s:
                anchor = '/* End PBXBuildFile section */'
                line = ('\t\t%s /* %s in %s */ = {isa = PBXBuildFile; fileRef = %s /* %s */;%s };\n'
                        % (bfile, base, kind, fref, base, settings))
                s = s.replace(anchor, line + anchor, 1)
            s, _ = insert_into_list(s, phase, 'files',
                                    '\t\t\t\t%s /* %s in %s */,' % (bfile, base, kind))

        # 3. Group membership -- a shared reference already belongs to a group
        if not shared_ref:
            s, _ = insert_into_list(s, group, 'children',
                                    '\t\t\t\t%s /* %s */,' % (fref, base))
        added.append(base)

    open(PROJ, 'w').write(s)
    print('registered in %s: %s' % (target, ', '.join(added)))


if __name__ == '__main__':
    main()
