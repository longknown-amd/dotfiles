[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# >>> sonar_thomas job env (SSH sessions only; added for the local SONAR agent; delete block to undo) >>>
if [ -n "$SSH_CONNECTION" ] && [ -f /mnt/raid0/users/thohuang/project/SONAR/.env ]; then
  eval "$(grep -E '^(MYSQL|CLICKHOUSE)_[A-Z_]+=' /mnt/raid0/users/thohuang/project/SONAR/.env | sed 's/^/export /')"
  export MYSQL_DATABASE=sonar_thomas CLICKHOUSE_DATABASE=sonar_thomas
fi
# <<< sonar_thomas job env <<<
