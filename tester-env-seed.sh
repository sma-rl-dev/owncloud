#!/usr/bin/env bash
# ownCloud deterministic acceptance seed (prospect stage).
# Theme: Northwind Design Studio file hub.
# Idempotent: re-running after reset OR on top of a seeded install yields the
# same asserted state (fixed users/passwords, fixed file contents, exactly one
# user share, exactly one link share, exactly one stored version of brief.txt).
# No randomness, no wall-clock input; link tokens are server-generated and are
# never asserted on.
# Env: CONTAINER (default tester-env-owncloud), PORT (default 8088).
set -euo pipefail

CONTAINER="${CONTAINER:-tester-env-owncloud}"
PORT="${PORT:-8088}"
BASE="http://localhost:${PORT}"
TESTER_AUTH="tester:tester12345"

occ() {
    docker exec "${CONTAINER}" su -s /bin/bash www-data \
        -c "php /var/www/html/occ $*" 2>&1
}

ensure_user() {
    local uid="$1" display="$2" pass="$3"
    docker exec -e "OC_PASS=${pass}" "${CONTAINER}" su -s /bin/bash www-data \
        -c "php /var/www/html/occ user:add --password-from-env --display-name='${display}' ${uid}" >/dev/null 2>&1 \
        || true
    docker exec -e "OC_PASS=${pass}" "${CONTAINER}" su -s /bin/bash www-data \
        -c "php /var/www/html/occ user:resetpassword --password-from-env ${uid}" >/dev/null 2>&1
    occ user:modify "${uid}" displayname "'${display}'" >/dev/null 2>&1 \
        || occ user:modify "${uid}" displayname "${display}" >/dev/null 2>&1 || true
    echo "    user ${uid} (${display}) ok"
}

dav() { # dav <METHOD> <path> [extra curl args...]; path is tester-relative
    local method="$1" path="$2"
    shift 2
    curl -fsS -u "${TESTER_AUTH}" -X "${method}" \
        "${BASE}/remote.php/dav/files/tester/${path}" "$@" >/dev/null
}

put_file() { # put_file <remote-path> ; body comes from stdin
    local path="$1"
    curl -fsS -u "${TESTER_AUTH}" -X PUT \
        "${BASE}/remote.php/dav/files/tester/${path}" \
        --data-binary @- >/dev/null
}

echo "==> ownCloud deterministic seed (Northwind Design Studio)"

# 1. Users (fixed credentials) and group.
ensure_user tester "Alex Rivera" "tester12345"
ensure_user teammate "Sam Chen" "teammate12345"
occ group:add studio >/dev/null 2>&1 || true
occ group:add-member studio -m tester -m teammate >/dev/null 2>&1 || true
echo "    group studio (tester, teammate) ok"

# 1a. Markup-named group for the group-name-escaping scenario: the angle
# brackets are part of the literal group name. Only tester is a member;
# studiowiki stays restricted to studio so nav fixtures are unaffected.
# NOTE: the occ() helper cannot carry this name (the container shell would
# parse the unquoted angle brackets as redirections), so quote it explicitly.
docker exec "${CONTAINER}" su -s /bin/bash www-data \
    -c 'php /var/www/html/occ group:add "<b>spotlight-deals</b>"' >/dev/null 2>&1 || true
docker exec "${CONTAINER}" su -s /bin/bash www-data \
    -c 'php /var/www/html/occ group:add-member "<b>spotlight-deals</b>" -m tester' >/dev/null 2>&1 || true
echo "    group <b>spotlight-deals</b> (tester) ok"

# 1b. Group-restricted nav app (Studio Wiki): shipped in the source tree at
# apps/studiowiki (baked into the image), enabled ONLY for group studio.
# admin is explicitly kept out of studio so the admin header app menu shows
# Files only, while studio members see the extra Studio Wiki entry.
occ group:remove-member studio -m admin >/dev/null 2>&1 || true
occ app:enable -g studio studiowiki >/dev/null 2>&1
echo "    studio wiki app (group-restricted to studio) ok"

# 2. Clean slate for counts: delete every seeded path (collection DELETE is
#    recursive), then clear trashbin + versions, so each run recreates files
#    fresh: only brief.txt (v1 -> v2 below) ends up with a stored version.
occ versions:cleanup tester teammate >/dev/null 2>&1 || true
occ trashbin:cleanup tester teammate >/dev/null 2>&1 || true
for victim in Projects Invoices Notes welcome.txt; do
    curl -fsS -u "${TESTER_AUTH}" -X DELETE \
        "${BASE}/remote.php/dav/files/tester/${victim}" >/dev/null 2>&1 || true
done
occ trashbin:cleanup tester teammate >/dev/null 2>&1 || true
occ versions:cleanup tester teammate >/dev/null 2>&1 || true

# 3. Folders (MKCOL 405 when they already exist is fine).
for d in Projects Projects/Website-Redesign Invoices Notes; do
    dav MKCOL "${d}" || true
done

# 4. Files with fixed realistic content (PUT overwrites => idempotent).
put_file "welcome.txt" <<'EOF'
Welcome to the Northwind Design Studio file hub.

Shared folders:
- Projects: active client work (shared with the studio group)
- Invoices: monthly billing records
- Notes: meeting notes and decisions

Please keep client files inside Projects so shares stay intact.
EOF

put_file "Projects/Website-Redesign/launch-checklist.md" <<'EOF'
# Website Redesign - Launch Checklist

- [x] Homepage mockup approved (2026-08-20)
- [x] Copy deck finalized (2026-08-25)
- [ ] Image assets compressed
- [ ] Staging link sent to client
- [ ] DNS cutover scheduled
EOF

put_file "Invoices/invoice-2026-08.txt" <<'EOF'
Northwind Design Studio - Invoice 2026-08
Client: Beacon Mobile App
Amount due: $4,200.00
Due date: 2026-09-15
Status: SENT
EOF

put_file "Notes/meeting-notes-2026-08-28.md" <<'EOF'
# Meeting notes - 2026-08-28

Attendees: Alex Rivera, Sam Chen
Topic: Website Redesign handoff

Decisions:
- Sam owns image compression by 2026-09-02.
- Alex sends the staging link after checklist items 3-4 close.
EOF

# brief.txt v1 then v2: leaves exactly one stored version (the v1 content).
put_file "Projects/Website-Redesign/brief.txt" <<'EOF'
Website Redesign - Project Brief (draft)
Client: Beacon Mobile App
Scope: homepage, pricing page, blog index.
Deadline: 2026-09-12
EOF
put_file "Projects/Website-Redesign/brief.txt" <<'EOF'
Website Redesign - Project Brief (final)
Client: Beacon Mobile App
Scope: homepage, pricing page, blog index.
Deadline: 2026-09-12
Owner: Alex Rivera
Launch readiness: GREEN
EOF

# team-photo.png: deterministic non-square (320x200) RGB PNG for the avatar
# cropper scenario (square images skip the cropper). Generated offline with
# stdlib-only python (zlib+struct, compress level 9): byte-identical on every
# run (33142 bytes, md5 15028fb1bb57cdfbabc7b800ededfe59). PUT once per seed;
# the Projects wipe above keeps it version-free like the other seeded files.
python3 - <<'PYEOF' | curl -fsS -u "${TESTER_AUTH}" -X PUT \
    "${BASE}/remote.php/dav/files/tester/Projects/Website-Redesign/team-photo.png" \
    --data-binary @- >/dev/null
import struct
import sys
import zlib
W, H = 320, 200
raw = bytearray()
for y in range(H):
    raw.append(0)
    for x in range(W):
        if (x - 260) ** 2 + (y - 55) ** 2 < 30 ** 2:
            px = (250, 200, 60)
        elif y < 130:
            px = (x * 255 // W, 120 + y // 2, 220)
        elif y < 150:
            px = (70, 140, 70)
        else:
            px = (40, 90, 160)
        raw += bytes(px)
def chunk(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
sys.stdout.buffer.write(
    b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    + chunk(b'IEND', b''))
PYEOF
echo "    files (6, brief.txt at v2 with 1 stored version + team-photo.png 320x200) ok"

# 5. Favorite on brief.txt (PROPPATCH is idempotent).
curl -fsS -u "${TESTER_AUTH}" -X PROPPATCH \
    "${BASE}/remote.php/dav/files/tester/Projects/Website-Redesign/brief.txt" \
    -H 'Content-Type: application/xml' \
    --data '<d:propertyupdate xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns"><d:set><d:prop><oc:favorite>1</oc:favorite></d:prop></d:set></d:propertyupdate>' >/dev/null
echo "    favorite (brief.txt) ok"

# 6. Shares: delete matching ones first so re-seed keeps exactly one of each.
ocs() { # ocs <METHOD> <api-path> [curl args...]
    local method="$1" api="$2"
    shift 2
    curl -fsS -u "${TESTER_AUTH}" -H 'OCS-APIRequest: true' -X "${method}" \
        "${BASE}/ocs/v1.php/apps/files_sharing/api/v1${api}" "$@"
}
share_ids_for_path() {
    ocs GET "/shares?format=json&path=$1" \
        | python3 -c 'import json,sys; [print(s["id"]) for s in json.load(sys.stdin)["ocs"]["data"]]'
}
for sid in $(share_ids_for_path "/Projects"); do
    ocs DELETE "/shares/${sid}" >/dev/null
done
for sid in $(share_ids_for_path "/Invoices/invoice-2026-08.txt"); do
    ocs DELETE "/shares/${sid}" >/dev/null
done
ocs POST "/shares?format=json" \
    --data-urlencode "path=/Projects" \
    --data-urlencode "shareType=0" \
    --data-urlencode "shareWith=teammate" \
    --data-urlencode "permissions=31" >/dev/null
ocs POST "/shares?format=json" \
    --data-urlencode "path=/Invoices/invoice-2026-08.txt" \
    --data-urlencode "shareType=3" >/dev/null
echo "    shares (Projects -> teammate, invoice-2026-08.txt link) ok"

# 7. Rescan file cache (safety net; WebDAV writes normally need none).
occ files:scan tester teammate >/dev/null 2>&1 || true

echo "==> Seed complete."
echo "    Credentials: admin/admin12345 (admin), tester/tester12345, teammate/teammate12345."
