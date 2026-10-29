#!/usr/bin/env zsh
# Preflight: собрать факты перед генерацией комплишена.
#
# Использование:
#   preflight.zsh [--fast] <command>
#
# Скрипт работает только на чтение: опрашивает --version и help, читает fpath,
# проверяет zpty/gate/compinit и печатает строки key=value. Он никогда не пишет
# в fpath, не запускает мутирующие команды и не использует сеть. Единственный
# побочный эффект — приватный временный compdump, который удаляется перед
# выходом.
#
# Устройство:
#   PREFLIGHT_DEFAULTS — значения по умолчанию для всех полей отчёта.
#   PREFLIGHT          — изменяемое состояние; каждая функция обновляет только
#                        свой срез и ничего не печатает.
#   _preflight_run     — цепочка: вызывает функции по порядку и после каждой
#                        завершившейся части печатает её поля через
#                        _preflight_emit.
#   _preflight_decide  — последний этап: по собранным фактам выбирает
#                        следующее действие и доступные уровни проверки.
#
# Отчёт всегда полный: если этап пропущен (нет команды, --fast), печатаются
# значения по умолчанию из PREFLIGHT_DEFAULTS.
#
# Контракт вывода:
#   - одна пара key=value на строку; значение — всё после первого '=';
#   - списки fpath склеены через ':';
#   - каждый ключ присутствует всегда, даже если значение пустое.
#
# Коды возврата:
#   0  отчёт собран
#   2  ошибка использования
#   3  команда не найдена
#
# --fast пропускает gate и проверку compinit (gate=skip, compinit=skip).
# Режим нужен для быстрых итераций по спекам, а не для финальной проверки.

# ---------------------------------------------------------------------------
# Состояние
# ---------------------------------------------------------------------------

typeset -A PREFLIGHT_DEFAULTS=(
  cmd                 ''
  cmd_path            ''
  cmd_version         unknown
  os                  unknown
  zsh                 "$ZSH_VERSION"
  fpath_env           ''
  fpath_interactive   ''
  fpath_clean         ''
  target              ''
  target_source       none
  target_writable     no
  target_candidates   ''
  existing_completion ''
  shadowed            no
  help                skip
  completion_hint     no
  pty                 no
  gate                skip
  gate_detail         ''
  compinit            skip
  decision            ''
  decision_reason     ''
  verification        unknown
)
# Единственное место, где перечислены все поля отчёта и их значения по
# умолчанию. Добавили поле — добавили строку здесь и в _preflight_emit.

typeset -A PREFLIGHT
# Текущее состояние. Ни одно поле не удаляется, поэтому отчёт не может
# оказаться частичным.

typeset -i PREFLIGHT_FAST=0
typeset -i PREFLIGHT_STOP=0
# PREFLIGHT_FAST: включён --fast.
# PREFLIGHT_STOP: --help уже обработан, цепочку запускать не нужно.

# ---------------------------------------------------------------------------
# Настройка
# ---------------------------------------------------------------------------

emulate -L zsh
# Сбрасываем опции к дефолтам zsh и оставляем изменения локальными. Иначе
# опции вызывающего shell (nullglob, shwordsplit, ...) могли бы изменить
# разбор массивов fpath и строк key=value.

typeset -g SCRIPT_NAME=${0:t}
# Имя файла, зафиксированное на верхнем уровне: внутри функций $0 — это имя
# функции, поэтому usage не может брать ${0:t} напрямую.

typeset -g DIR=${0:A:h}
# Абсолютный каталог скрипта: ${0:A} разворачивает symlink и делает путь
# абсолютным, :h берёт родительский каталог. Нужен, чтобы вызывать соседние
# скрипты независимо от $PWD вызывающего.

# ---------------------------------------------------------------------------
# Служебные функции
# ---------------------------------------------------------------------------

_preflight_cli_usage() {
  # Справка самого preflight. Help целевой команды — _preflight_target_help.
  print -u2 "usage: $SCRIPT_NAME [--fast] <command>"
  # -u2 — в stderr, чтобы stdout оставался чистым для key=value; SCRIPT_NAME
  # зафиксирован на верхнем уровне, потому что внутри функции $0 — её имя.
  return 2
}

_preflight_reset() {
  PREFLIGHT=()
  PREFLIGHT_FAST=0
  PREFLIGHT_STOP=0
  # Скрипт запускается один раз, но reset делает состояние предсказуемым и
  # позволяет вызывать _preflight_run повторно (например, из тестов).

  local key
  for key in ${(k)PREFLIGHT_DEFAULTS}; do
    PREFLIGHT[$key]=${PREFLIGHT_DEFAULTS[$key]}
  done
  # Копируем defaults в изменяемое состояние. Копия, а не ссылка: функции
  # меняют PREFLIGHT, defaults остаются эталоном.
}

_preflight_emit() {
  local key
  for key in "$@"; do
    print -r -- "$key=${PREFLIGHT[$key]}"
  done
  # Печатает только переданные поля, в порядке аргументов. Вызывается после
  # каждого этапа цепочки, поэтому порядок строк отчёта задаётся _preflight_run,
  # а не порядком ключей в ассоциативном массиве.
}

# ---------------------------------------------------------------------------
# Этапы цепочки
# ---------------------------------------------------------------------------

_preflight_parse_args() {
  while (( $# )); do
    # Разбираем только ведущие опции; первое слово не-опция — команда.
    case $1 in
      (--fast) PREFLIGHT_FAST=1; shift ;;
      (--help|-h) _preflight_cli_usage; PREFLIGHT_STOP=1; return 0 ;;
      # Явный запрос справки — успех; STOP не даёт цепочке продолжиться.
      (--) shift; break ;;
      # Конец опций: следующее слово — команда, даже если начинается с '-'.
      (-*) _preflight_cli_usage; return 2 ;;
      # Неизвестная опция: не угадываем, сразу ошибка.
      (*) break ;;
    esac
  done

  if (( $# != 1 )); then
    _preflight_cli_usage
    return 2
  fi
  # Ровно одна команда: preflight описывает одну цель, а не семейство.

  PREFLIGHT[cmd]=$1
  return 0
}

_preflight_identity() {
  # Идентичность цели: путь в PATH и версия из --version.
  PREFLIGHT[cmd_path]=$(command -v "${PREFLIGHT[cmd]}" 2>/dev/null)
  # command -v резолвит PATH, не запуская команду. 2>/dev/null не даёт
  # отсутствию команды засорить отчёт строкой ошибки.

  if [[ -n ${PREFLIGHT[cmd_path]} ]]; then
    local raw
    raw=$("${PREFLIGHT[cmd]}" --version 2>/dev/null | head -n 1)
    # Запускаем только --version: это безопасно и не меняет состояние.
    # head -n 1 — некоторые инструменты печатают версию в несколько строк.

    raw=${raw%$'\r'}
    # Убираем CR из CRLF-вывода; иначе \r попадёт внутрь значения.

    [[ -n $raw ]] && PREFLIGHT[cmd_version]=$raw
    # Пустой вывод — не версия: остаётся default "unknown".
  fi

  PREFLIGHT[cmd_version]=${PREFLIGHT[cmd_version]//$'\n'/ }
  # Страховка: перевод строки внутри значения разорвал бы одно поле на два.
}

_preflight_os() {
  PREFLIGHT[os]=$(uname -s 2>/dev/null)
  # Darwin/Linux. Важно для BSD-vs-GNU разбора help и поведения утилит.

  [[ -n ${PREFLIGHT[os]} ]] || PREFLIGHT[os]=unknown
  PREFLIGHT[zsh]=$ZSH_VERSION
  # Версия zsh уже в памяти; подпроцесс не нужен.
}

_preflight_fpath() {
  local -A fp
  # Вывод check-fpath --porcelain, разобранный в ассоциативный массив.

  local line key value
  for line in ${(f)"$(zsh "$DIR/check-fpath.zsh" --porcelain "${PREFLIGHT[cmd]}" 2>/dev/null)"}; do
    # (f) режет по переводам строк. check-fpath — отдельный процесс намеренно:
    # он инкапсулирует interactive/clean fpath и порядок кандидатов, поэтому
    # здесь эта логика не дублируется.

    [[ $line == *=* ]] || continue
    # Пропускаем строки без '=' (шум rc-файлов, попавший в stdout).

    key=${line%%=*}
    # Всё до ПЕРВОГО '='.

    value=${line#*=}
    # Всё после первого '='; '=' внутри значения сохраняется.

    fp[$key]=$value
  done

  PREFLIGHT[fpath_env]=${fp[fpath_env]:-}
  PREFLIGHT[fpath_interactive]=${fp[fpath_interactive]:-}
  PREFLIGHT[fpath_clean]=${fp[fpath_clean]:-}
  # Три представления fpath: экспортированный FPATH, реальный интерактивный и
  # путь без FPATH. Разница объясняет stale-записи и перекрытия.

  PREFLIGHT[existing_completion]=${fp[first]:-}
  PREFLIGHT[shadowed]=${fp[shadowed]:-no}
  # first — выигравший _cmd; shadowed — есть ли ещё копии. Правка перекрытого
  # файла бесполезна, поэтому это сигнал стоп/предупредить.

  local -a fpath_dirs writable_dirs
  fpath_dirs=( ${(s.:.)fp[fpath_interactive]} )
  # (s.:.) режет по ':', разделителю fpath. Интерактивный fpath — то, что
  # реально видит пользователь, поэтому он здесь источник истины.

  local d
  for d in $fpath_dirs; do
    [[ -d $d && -w $d ]] && writable_dirs+=($d)
    # -d: это каталог; -w: прокси права записи. Настоящая пробная запись
    # нарушила бы контракт "только чтение", поэтому -w — осознанный компромисс.
  done

  PREFLIGHT[target_candidates]=${(j.:.)writable_dirs}
  # Кандидаты для новой команды. Автоматически цель не выбирается: первый
  # writable-каталог может быть исходником, bundle приложения или Homebrew.
}

_preflight_target() {
  PREFLIGHT[target]=''
  PREFLIGHT[target_source]=none
  PREFLIGHT[target_writable]=no
  # Сбрасываем срез, чтобы функция была идемпотентной.

  if [[ -n ${PREFLIGHT[cmd_path]} && -n ${PREFLIGHT[existing_completion]} ]]; then
    PREFLIGHT[target]=${PREFLIGHT[existing_completion]}
    PREFLIGHT[target_source]=existing
    # Только существующий _cmd выбирает цель автоматически: обновлять нужно
    # тот файл, который реально выигрывает в fpath.
  fi

  if [[ -n ${PREFLIGHT[target]} && -d ${PREFLIGHT[target]} && -w ${PREFLIGHT[target]} ]]; then
    PREFLIGHT[target_writable]=yes
  fi
  # Проверяем запись именно в выбранный target, а не в fpath вообще. _cmd в
  # root-owned каталоге даст writable=no — это сигнал остановиться.
}

_preflight_target_help() {
  # Справка целевой команды (не CLI preflight): --help/-h/help/--help-all.
  if [[ -z ${PREFLIGHT[cmd_path]} ]]; then
    return 0
    # Команды нет: help остаётся skip, completion_hint — no.
  fi

  local text
  if text=$(zsh "$DIR/probe-help.zsh" "${PREFLIGHT[cmd]}" 2>/dev/null); then
    PREFLIGHT[help]=ok
    # probe-help уже перебирает --help/-h/help/--help-all и принимает только
    # help-подобный вывод; здесь эта логика не повторяется.

    [[ ${text:l} == *completion* ]] && PREFLIGHT[completion_hint]=yes
    # Эвристика, не доказательство: в help есть слово completion/completions.
    # Она говорит лишь "поищи генератор"; C0 всё равно подтверждается при
    # генерации.
  else
    PREFLIGHT[help]=missing
  fi
}

_preflight_pty() {
  if zmodload zsh/zpty 2>/dev/null; then
    local session="gwzpreflight$$"
    zpty -d "$session" 2>/dev/null
    # Уникальное имя сессии (PID) защищает от коллизий параллельных запусков;
    # zpty -d убирает stale-сессию после прошлого краша.

    if zpty "$session" /bin/sh -c true 2>/dev/null; then
      PREFLIGHT[pty]=yes
      zpty -d "$session" 2>/dev/null
      # Единственная надёжная проверка: реально выделить PTY и запустить самый
      # дешёвый процесс. $options[zle] и `zsh -i` без tty могут показывать
      # "on", хотя completion остаётся нерабочим.
    fi
  fi
}

_preflight_gate() {
  if (( PREFLIGHT_FAST )) || [[ ${PREFLIGHT[pty]} != yes || -z ${PREFLIGHT[cmd_path]} ]]; then
    return 0
    # Gate нужен, только если есть PTY, команда существует и это не --fast.
  fi

  local g rc
  g=$(zsh "$DIR/gate.zsh" 2>/dev/null)
  rc=$?
  # gate.zsh гоняет стенд на tests/fixtures/_demo. Его код возврата — это
  # контракт: 0 pass, 1 fail, 77 no PTY. Вывод для решения не парсим.

  case $rc in
    (0) PREFLIGHT[gate]=pass ;;
    (77) PREFLIGHT[gate]=no-pty ;;
    (*) PREFLIGHT[gate]=fail; PREFLIGHT[gate_detail]=$g ;;
  esac

  PREFLIGHT[gate_detail]=${PREFLIGHT[gate_detail]//$'\n'/; }
  PREFLIGHT[gate_detail]=${PREFLIGHT[gate_detail]//$'\r'/}
  # Схлопываем многострочный fail в одну строку, чтобы отчёт оставался
  # разбираемым.
}

_preflight_compinit() {
  if (( PREFLIGHT_FAST )) || [[ -z ${PREFLIGHT[cmd_path]} ]]; then
    return 0
  fi

  local tmp
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/gwz-preflight.XXXXXX") || tmp=
  # Приватный каталог для dump: никогда не трогаем собственный compdump
  # пользователя. TMPDIR с fallback на /tmp сохраняет переносимость.

  if [[ -n $tmp ]]; then
    if zsh -f -c 'autoload -Uz compinit; compinit -u -d "$1"; [[ ${+_comps} -eq 1 ]]' \
        -- "$tmp/zcompdump" 2>/dev/null; then
      PREFLIGHT[compinit]=ok
    else
      PREFLIGHT[compinit]=fail
    fi
    # zsh -f: без rc-файлов; -u: без prompt про insecure-каталоги;
    # -d: свой dump. ${+_comps} -eq 1 доказывает, что compinit реально
    # заполнил карту регистрации. Это "L2 возможен", а не "комплишен верен".
    rm -rf -- "$tmp"
    # Убираем за собой: preflight не должен оставлять состояние.
  else
    PREFLIGHT[compinit]=fail
    # Нет временного каталога — L2 не проверить; сообщаем, а не падаем.
  fi
}

# ---------------------------------------------------------------------------
# Решение
# ---------------------------------------------------------------------------

_preflight_decide() {
  if [[ -z ${PREFLIGHT[cmd_path]} ]]; then
    PREFLIGHT[decision]=stop
    PREFLIGHT[decision_reason]=command-not-found
    PREFLIGHT[verification]=none
    return
    # Без команды нечего генерировать и нечего проверять.
  fi

  if [[ -n ${PREFLIGHT[existing_completion]} ]]; then
    PREFLIGHT[decision]=use-existing
    PREFLIGHT[decision_reason]=native-completion-exists
    # C1/C2: нативный комплишен уже выигрывает в fpath. По умолчанию его
    # используют, а не дублируют; обновление — только по явному запросу.
  elif [[ ${PREFLIGHT[target_source]} == none ]]; then
    PREFLIGHT[decision]=choose-target
    if [[ -n ${PREFLIGHT[target_candidates]} ]]; then
      PREFLIGHT[decision_reason]=target-not-selected
      # Кандидаты есть, но preflight сознательно не выбирает за пользователя.
    else
      PREFLIGHT[decision_reason]=no-writable-target
      # В fpath нет ни одного записываемого каталога.
    fi
  elif [[ ${PREFLIGHT[target_writable]} != yes ]]; then
    PREFLIGHT[decision]=choose-target
    PREFLIGHT[decision_reason]=target-not-writable
    # Цель известна, но писать в неё нельзя.
  elif [[ ${PREFLIGHT[completion_hint]} == yes ]]; then
    PREFLIGHT[decision]=try-generator
    PREFLIGHT[decision_reason]=help-mentions-completion
    # C0: сначала проверить `cmd completion zsh`, только потом писать руками.
  elif [[ ${PREFLIGHT[help]} == ok ]]; then
    PREFLIGHT[decision]=generate-from-help
    PREFLIGHT[decision_reason]=help-available
    # C3: обычная генерация из --help.
  else
    PREFLIGHT[decision]=fallback-help
    PREFLIGHT[decision_reason]=help-missing
    # C8: man, --help-all, исходники, нативный комплишен.
  fi

  if [[ ${PREFLIGHT[gate]} == skip || ${PREFLIGHT[compinit]} == skip ]]; then
    PREFLIGHT[verification]=unknown
    # --fast не проверял возможность L2/L3; не выдаём предположение за факт.
    return
  fi

  local -a levels=( l1 )
  [[ ${PREFLIGHT[compinit]} == ok ]] && levels+=(l2)
  [[ ${PREFLIGHT[gate]} == pass ]] && levels+=(l3)
  PREFLIGHT[verification]=${(j:-:)levels}
  # L1 возможен всегда; L2 — если compinit создал карту регистрации;
  # L3 — только если gate подтвердил, что harness работает.
}

# ---------------------------------------------------------------------------
# Цепочка
# ---------------------------------------------------------------------------

_preflight_run() {
  _preflight_reset

  _preflight_parse_args "$@"
  local -i rc=$?
  if (( rc != 0 )); then
    return $rc
    # Ошибка использования: печатать отчёт не нужно.
  fi
  (( PREFLIGHT_STOP )) && return 0
  # --help уже напечатал usage; цепочку не запускаем.

  # Каждый этап только обновляет PREFLIGHT. _preflight_emit вызывается сразу
  # после него, поэтому отчёт печатается по мере готовности частей, а порядок
  # строк задаётся здесь, а не порядком ключей в массиве.
  _preflight_identity
  _preflight_emit cmd cmd_path cmd_version

  _preflight_os
  _preflight_emit os zsh

  _preflight_fpath
  _preflight_emit fpath_env fpath_interactive fpath_clean

  _preflight_target
  _preflight_emit target target_source target_writable target_candidates \
    existing_completion shadowed

  _preflight_target_help
  _preflight_emit help completion_hint

  _preflight_pty
  _preflight_emit pty

  _preflight_gate
  _preflight_emit gate gate_detail

  _preflight_compinit
  _preflight_emit compinit

  _preflight_decide
  _preflight_emit decision decision_reason verification

  [[ -n ${PREFLIGHT[cmd_path]} ]] || return 3
  # Команды нет: отчёт уже напечатан для диагностики, но код возврата говорит
  # вызывающему остановиться. Не путать с успешным запуском.

  return 0
}

_preflight_run "$@"
