#!/usr/bin/env zsh
# Показать, откуда берётся файл zsh-комплишена и какая копия выигрывает.
#
# Использование:
#   collect/fpath.zsh [--porcelain] <command>
#
# Обычный вывод — человеческий отчёт: FPATH из окружения, интерактивный fpath,
# чистый fpath без FPATH и все копии _command в порядке приоритета. С
# --porcelain печатаются стабильные строки key=value для preflight:
#   fpath_env, fpath_interactive, fpath_clean, candidates, first, count, shadowed
# Списки склеены через ':' (разделитель fpath). Человеческий формат оставлен без
# изменений, чтобы не ломать существующих вызывающих и self-check.

# ---------------------------------------------------------------------------
# Настройка
# ---------------------------------------------------------------------------

emulate -L zsh
# Локальные опции: разбор массивов и globbing не должны зависеть от
# вызывающего shell.

typeset -g SCRIPT_NAME=${0:t}
# Имя файла для сообщений об использовании.

__usage() {
  print -u2 "usage: $SCRIPT_NAME [--porcelain] <command>"
  return 2
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

__main() {
  local porcelain=0
  # 0 — человеческий отчёт (обратная совместимость), 1 — key=value.

  while (( $# )); do
    case $1 in
      (--porcelain) porcelain=1; shift ;;
      (--help|-h) __usage; return 0 ;;
      (--) shift; break ;;
      # Явный конец опций, чтобы команда могла начинаться с '-'.
      (-*) __usage; return 2 ;;
      (*) break ;;
    esac
  done

  if (( $# != 1 )); then
    __usage
    return 2
  fi

  local cmd=$1
  local file="_$cmd"
  # Файл, который zsh попытается автозагрузить для этой команды.

  # --- Собираем представления fpath ----------------------------------------

  local -a interactive clean candidates
  # interactive: то, что реально видит интерактивный shell пользователя.
  # clean: то же с отключённым FPATH, чтобы увидеть stale-записи.
  # candidates: все копии _cmd в порядке приоритета интерактивного fpath.

  interactive=( ${(f)"$(zsh -ic 'print -l $fpath' 2>/dev/null)"} )
  # -i обязателен: fpath собирается rc-файлами интерактивного shell. (f) режет
  # вывод на элементы массива; 2>/dev/null убирает шум rc-файлов.

  clean=( ${(f)"$(env -u FPATH zsh -ic 'print -l $fpath' 2>/dev/null)"} )
  # env -u FPATH убирает экспортированный FPATH только для этого процесса,
  # поэтому видно, что shell использовал бы без этого override.

  local d
  for d in $interactive; do
    [[ -f $d/$file ]] && candidates+=($d)
    # Простая проверка файла, по порядку. Порядок — это и есть суть: первый
    # найденный выигрывает, каждая следующая копия перекрыта.
  done

  # --- Машиночитаемый режим ------------------------------------------------

  if (( porcelain )); then
    print -r -- "fpath_env=${FPATH:-}"
    # Экспортированное значение или пусто. Оставляем как есть: это факт, а не
    # оценка.

    print -r -- "fpath_interactive=${(j.:.)interactive}"
    print -r -- "fpath_clean=${(j.:.)clean}"
    # (j.:.) склеивает элементы массива через ':', как в самом fpath.

    print -r -- "candidates=${(j.:.)candidates}"
    # Все копии, не только победитель: вызывающий может предупредить об
    # остальных.

    print -r -- "first=${candidates[1]:-}"
    # Победитель или пусто. ${...:-} защищает от ошибки "unset parameter".

    print -r -- "count=${#candidates}"
    # Число копий; также отличает "нет" от "одна".

    if (( ${#candidates} > 1 )); then
      print -r -- "shadowed=yes"
    else
      print -r -- "shadowed=no"
    fi
    # Больше одной копии — правка любой, кроме первой, ни на что не влияет.

    return 0
  fi

  # --- Человекочитаемый режим ----------------------------------------------

  print -r -- 'FPATH environment:'
  if [[ -n ${FPATH:-} ]]; then
    print -r -- "$FPATH"
  else
    print -r -- '(unset)'
  fi

  print -r -- ''
  print -r -- 'Interactive fpath:'
  if (( ${#interactive} )); then
    print -rl -- "${(@)interactive}"
  else
    print -r -- '(failed)'
  fi

  print -r -- ''
  print -r -- 'Clean fpath (FPATH unset):'
  if (( ${#clean} )); then
    print -rl -- "${(@)clean}"
  else
    print -r -- '(failed)'
  fi

  print -r -- ''
  print -r -- "Candidates for $file in interactive fpath order:"
  (( ${#candidates} )) && print -rl -- "${(@)candidates}"
  # При пустом candidates под заголовком ничего не печатается; пояснение ниже
  # всё равно объясняет правило перекрытия.

  print -r -- ''
  print -r -- 'First match wins. If the target directory is not first, a later copy is shadowed.'
  return 0
}

__main "$@"
