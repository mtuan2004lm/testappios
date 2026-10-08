#!/bin/bash
# Chay ca server (cong 3000) va web (cong 5173) bang 1 lenh.  Dung:  ./start.sh   |  Dung lai: Ctrl+C
cd "$(dirname "$0")" || exit 1

# Giai phong cong neu con tien trinh cu
for port in 3000 5173; do
  pids=$(lsof -ti :$port 2>/dev/null)
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null
done

# Kiem tra Postgres.app dang chay
if ! /Applications/Postgres.app/Contents/Versions/latest/bin/pg_isready -q 2>/dev/null; then
  echo "!! Postgres chua chay. Mo ung dung Postgres.app, bam Start, roi chay lai ./start.sh"
  exit 1
fi

trap 'kill 0' EXIT INT TERM
(cd server && npm run dev) &
sleep 2
(cd client && npm run dev) &
wait
