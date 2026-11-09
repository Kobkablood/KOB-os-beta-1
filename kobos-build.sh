#!/usr/bin/env bash
# KOBos Beta 1 — собственный дистрибутив Linux на базе Debian 13 (trixie) + XFCE.
# Запуск (на Debian/Ubuntu, на реальной машине, в VM или WSL2):
#   chmod +x kobos-build.sh && sudo ./kobos-build.sh
# Результат: kobos-build/kobos-beta1-amd64.hybrid.iso
set -euo pipefail

# ---- Название и версия: меняются только здесь ----
OS_NAME="KOBos"                 # как называется система
OS_VERSION="Beta 1"             # версия
IMAGE_NAME="kobos-beta1"        # имя ISO-файла (латиница, без пробелов)
VOLUME_ID="KOBOS_BETA1"         # метка диска (латиница, без пробелов, до 32 символов)
HOST_NAME="kobos"               # имя компьютера
LIVE_USER="kobos"               # логин в live-режиме (пароль: live)
# --------------------------------------------------

[ "$(id -u)" -eq 0 ] || { echo "Запустите через sudo: sudo ./kobos-build.sh"; exit 1; }

WORKDIR="$(pwd)/kobos-build"

echo "==> Устанавливаю инструменты сборки"
apt-get update
apt-get install -y live-build debootstrap squashfs-tools xorriso \
  grub-pc-bin grub-efi-amd64-bin mtools dosfstools qemu-system-x86 ovmf \
  curl ca-certificates gnupg

mkdir -p "$WORKDIR"
cd "$WORKDIR"
lb clean --purge 2>/dev/null || true

echo "==> Конфигурация live-build"
lb config \
  --distribution trixie \
  --mode debian \
  --mirror-bootstrap http://deb.debian.org/debian/ \
  --mirror-chroot http://deb.debian.org/debian/ \
  --mirror-binary http://deb.debian.org/debian/ \
  --parent-mirror-bootstrap http://deb.debian.org/debian/ \
  --parent-mirror-chroot http://deb.debian.org/debian/ \
  --parent-mirror-binary http://deb.debian.org/debian/ \
  --parent-mirror-chroot-security http://security.debian.org/debian-security/ \
  --parent-mirror-binary-security http://security.debian.org/debian-security/ \
  --parent-mirror-chroot-volatile none \
  --parent-mirror-binary-volatile none \
  --mirror-chroot-security http://security.debian.org/debian-security/ \
  --mirror-binary-security http://security.debian.org/debian-security/ \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --archive-areas "main contrib non-free non-free-firmware" \
  --linux-flavours amd64 \
  --debian-installer false \
  --firmware-chroot true \
  --iso-application "$OS_NAME" \
  --iso-volume "$VOLUME_ID" \
  --bootappend-live "boot=live components quiet splash locales=ru_RU.UTF-8 keyboard-layouts=us,ru,ua,de keyboard-options=grp:alt_shift_toggle timezone=Europe/Berlin username=$LIVE_USER"

mkdir -p config/package-lists config/hooks/live config/archives \
         config/includes.chroot/etc/skel/Desktop \
         config/includes.chroot/etc/skel/.config \
         config/includes.chroot/etc/apt/sources.list.d \
         config/includes.chroot/usr/share/keyrings \
         config/includes.chroot_before_packages/usr/share/keyrings

echo "==> Репозиторий Brave (официальный, скачивается напрямую у Brave)"
BRAVE_REPO="https://brave-browser-apt-release.s3.brave.com"
curl -fsSL "$BRAVE_REPO/brave-browser-archive-keyring.gpg" \
  -o config/includes.chroot_before_packages/usr/share/keyrings/brave-browser-archive-keyring.gpg
cp config/includes.chroot_before_packages/usr/share/keyrings/brave-browser-archive-keyring.gpg \
   config/includes.chroot/usr/share/keyrings/brave-browser-archive-keyring.gpg
# Для сборки образа:
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] $BRAVE_REPO/ stable main" \
  > config/archives/brave.list.chroot
# Для установленной системы (чтобы Brave обновлялся сам):
curl -fsSL "$BRAVE_REPO/brave-browser.sources" \
  -o config/includes.chroot/etc/apt/sources.list.d/brave-browser-release.sources

# Brave — браузер по умолчанию
cat > config/includes.chroot/etc/skel/.config/mimeapps.list <<'EOF'
[Default Applications]
text/html=brave-browser.desktop
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
x-scheme-handler/about=brave-browser.desktop
x-scheme-handler/unknown=brave-browser.desktop
EOF

echo "==> Виджеты (Conky): температура CPU/GPU, погода, время, дата, экранное время"
mkdir -p config/includes.chroot/usr/local/bin \
         config/includes.chroot/etc/skel/.config/conky \
         config/includes.chroot/etc/skel/.config/autostart

# --- Название процессора ---
cat > config/includes.chroot/usr/local/bin/kobos-cpu-name <<'EOF'
#!/bin/sh
n=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//; s/([RMT]*)//g; s/  */ /g')
echo "${n:-н/д}" | cut -c1-38
EOF

# --- Температура процессора ---
cat > config/includes.chroot/usr/local/bin/kobos-cpu-temp <<'EOF'
#!/bin/sh
for h in /sys/class/hwmon/hwmon*; do
  n=$(cat "$h/name" 2>/dev/null)
  case "$n" in
    coretemp|k10temp|zenpower)
      for f in "$h"/temp*_input; do
        l=$(cat "${f%_input}_label" 2>/dev/null)
        case "$l" in
          "Package id 0"|Tctl|Tdie) echo "$(( $(cat "$f") / 1000 ))°C"; exit 0;;
        esac
      done
      echo "$(( $(cat "$h/temp1_input") / 1000 ))°C"; exit 0;;
  esac
done
echo "н/д"
EOF

# --- Видеокарта: название и температура (NVIDIA, AMD, Intel) ---
cat > config/includes.chroot/usr/local/bin/kobos-gpu <<'EOF'
#!/bin/sh
what="$1"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
  case "$what" in
    name) nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | cut -c1-38;;
    temp) echo "$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader | head -1)°C";;
  esac
  exit 0
fi
case "$what" in
  name)
    n=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | cut -d: -f3- | sed 's/^ *//; s/ (rev.*//')
    echo "${n:-н/д}" | cut -c1-38;;
  temp)
    for h in /sys/class/drm/card*/device/hwmon/hwmon*; do
      f="$h/temp1_input"
      if [ -r "$f" ]; then echo "$(( $(cat "$f") / 1000 ))°C"; exit 0; fi
    done
    echo "н/д";;
esac
EOF

# --- Погода (wttr.in). Город: файл ~/.config/kobos/city (латиницей), иначе по IP ---
cat > config/includes.chroot/usr/local/bin/kobos-weather <<'EOF'
#!/bin/sh
CITY=""
[ -f "$HOME/.config/kobos/city" ] && CITY=$(tr ' ' '+' < "$HOME/.config/kobos/city")
CACHE="/tmp/kobos-weather.$(id -u)"
if [ -f "$CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$CACHE") )) -lt 600 ]; then
  cat "$CACHE"; exit 0
fi
out=$(curl -fsS -m 8 "https://wttr.in/${CITY}?format=%l:+%t,+%C&lang=ru" 2>/dev/null)
if [ -n "$out" ]; then
  echo "$out" > "$CACHE"; echo "$out"
elif [ -f "$CACHE" ]; then
  cat "$CACHE"
else
  echo "нет сети"
fi
EOF

# --- Экранное время: считает только время активной работы (без простоя > 2 мин) ---
cat > config/includes.chroot/usr/local/bin/kobos-screentime-daemon <<'EOF'
#!/bin/sh
DIR="$HOME/.cache/kobos"
mkdir -p "$DIR"
while true; do
  sleep 30
  idle=$(xprintidle 2>/dev/null || echo 999999999)
  if [ "$idle" -lt 120000 ]; then
    f="$DIR/screentime-$(date +%F)"
    cur=$(cat "$f" 2>/dev/null || echo 0)
    echo $((cur + 30)) > "$f"
  fi
done
EOF

cat > config/includes.chroot/usr/local/bin/kobos-screentime <<'EOF'
#!/bin/sh
f="$HOME/.cache/kobos/screentime-$(date +%F)"
s=$(cat "$f" 2>/dev/null || echo 0)
printf '%dч %02dм\n' $((s / 3600)) $(((s % 3600) / 60))
EOF

chmod +x config/includes.chroot/usr/local/bin/kobos-*

# --- Внешний вид виджета ---
cat > config/includes.chroot/etc/skel/.config/conky/kobos.conf <<'EOF'
conky.config = {
  alignment = 'top_right',
  gap_x = 30,
  gap_y = 60,
  minimum_width = 300,
  maximum_width = 300,
  own_window = true,
  own_window_type = 'desktop',
  own_window_class = 'Conky',
  own_window_argb_visual = true,
  own_window_argb_value = 110,
  own_window_colour = '000000',
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  double_buffer = true,
  update_interval = 2,
  use_xft = true,
  font = 'Noto Sans:size=10',
  default_color = 'FFFFFF',
  color1 = '7FD1FF',
  color2 = 'AAAAAA',
  draw_shades = false,
  draw_outline = false,
  draw_borders = false,
  border_inner_margin = 16,
  override_utf8_locale = true,
}

conky.text = [[
${color1}${font Noto Sans:size=38:bold}${time %H:%M}${font}${color}
${time %A, %d %B %Y}
${color2}${hr 1}${color}
${color1}${font Noto Sans:size=9:bold}ПОГОДА${font}${color}
${execi 600 kobos-weather}
${color2}${hr 1}${color}
${color1}${font Noto Sans:size=9:bold}ПРОЦЕССОР${font}${color}
${execi 3600 kobos-cpu-name}
${execi 5 kobos-cpu-temp}   загрузка ${cpu cpu0}%
${color1}${font Noto Sans:size=9:bold}ВИДЕОКАРТА${font}${color}
${execi 3600 kobos-gpu name}
${execi 5 kobos-gpu temp}
${color2}${hr 1}${color}
${color1}${font Noto Sans:size=9:bold}ЭКРАННОЕ ВРЕМЯ${font}${color}
сегодня: ${execi 60 kobos-screentime}
]]
EOF

# --- Автозапуск виджета и счётчика экранного времени ---
cat > config/includes.chroot/etc/skel/.config/autostart/kobos-conky.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=KOBos виджеты
Exec=sh -c 'sleep 5; exec conky -c "$HOME/.config/conky/kobos.conf"'
X-GNOME-Autostart-enabled=true
EOF

cat > config/includes.chroot/etc/skel/.config/autostart/kobos-screentime.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=KOBos экранное время
Exec=/usr/local/bin/kobos-screentime-daemon
X-GNOME-Autostart-enabled=true
EOF

echo "==> Дополнительно: док (Plank), Steam, терминал, экранная клавиатура, настройки, учётная запись"
mkdir -p config/includes.chroot/etc/skel/.config/plank/dock1/launchers

# --- Док внизу экрана (Plank): значки приложений ---
dockitem() {  # $1 = номер для порядка, $2 = имя .desktop-файла
  printf '[PlankDockItemPreferences]\nLauncher=file:///usr/share/applications/%s\n' "$2" \
    > "config/includes.chroot/etc/skel/.config/plank/dock1/launchers/$1-${2%.desktop}.dockitem"
}
dockitem 01 brave-browser.desktop
dockitem 02 thunar.desktop
dockitem 03 xfce4-terminal.desktop
dockitem 04 steam.desktop
dockitem 05 xfce-settings-manager.desktop
dockitem 06 mugshot.desktop
dockitem 07 onboard.desktop
dockitem 08 kobos-language.desktop
dockitem 09 kobos-appearance.desktop

cat > config/includes.chroot/etc/skel/.config/autostart/kobos-dock.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=KOBos док
Exec=plank
X-GNOME-Autostart-enabled=true
EOF

# --- Смена языка системы (окно выбора) ---
mkdir -p config/includes.chroot/usr/share/applications \
         config/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf.d

cat > config/includes.chroot/usr/local/bin/kobos-language <<'EOF'
#!/bin/sh
choice=$(zenity --list --radiolist --title="Язык / Language" \
  --text="Выберите язык системы. Он применится после выхода и повторного входа." \
  --column="" --column="Код" --column="Язык" --hide-column=2 --print-column=2 \
  --width=380 --height=320 \
  TRUE  ru_RU.UTF-8 "Русский" \
  FALSE en_US.UTF-8 "English" \
  FALSE uk_UA.UTF-8 "Українська" \
  FALSE de_DE.UTF-8 "Deutsch") || exit 0
[ -n "$choice" ] || exit 0
if busctl call org.freedesktop.Accounts "/org/freedesktop/Accounts/User$(id -u)" \
     org.freedesktop.Accounts.User SetLanguage s "$choice" >/dev/null 2>&1; then
  if zenity --question --text="Язык изменён. Выйти из системы сейчас, чтобы применить?"; then
    xfce4-session-logout --logout
  fi
else
  zenity --error --text="Не удалось изменить язык отсюда. Выберите язык на экране входа: меню языка в верхней панели."
fi
EOF
chmod +x config/includes.chroot/usr/local/bin/kobos-language

cat > config/includes.chroot/usr/share/applications/kobos-language.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Язык / Language
Exec=kobos-language
Icon=preferences-desktop-locale
Terminal=false
Categories=Settings;
EOF

# Экран входа: язык, раскладка, сеанс, питание в верхней панели
cat > config/includes.chroot/etc/lightdm/lightdm-gtk-greeter.conf.d/50-kobos.conf <<'EOF'
[greeter]
indicators = ~host;~spacer;~clock;~spacer;~language;~layout;~session;~a11y;~power
EOF

# --- Внешний вид: кнопки окон как в macOS, цвета обоев, дока и заголовков ---
cat > config/hooks/live/0300-kobos-theme.hook.chroot <<'EOF'
#!/bin/sh
# Тема окон KOBos-Mac: тёмный заголовок и цветные кнопки слева (красная, жёлтая, зелёная)
SRC=/usr/share/themes/Default/xfwm4
DST=/usr/share/themes/KOBos-Mac/xfwm4
[ -d "$SRC" ] || { echo "ВНИМАНИЕ: нет темы Default для xfwm4, пропускаю"; exit 0; }
if command -v magick >/dev/null 2>&1; then IM="magick"; ID="magick identify"; else IM="convert"; ID="identify"; fi
mkdir -p "$DST"
cp -a "$SRC/." "$DST/"
cd "$DST" || exit 0
size=$($ID -format '%wx%h' close-active.xpm 2>/dev/null) || { echo "ВНИМАНИЕ: нет ImageMagick, пропускаю"; exit 0; }
w=${size%x*}; h=${size#*x}
cx=$((w / 2)); cy=$((h / 2)); r=5
[ "$w" -lt 14 ] && r=4
circle() { $IM -size "${w}x${h}" xc:none -fill "$2" -draw "circle $cx,$cy $cx,$((cy - r))" "xpm:$1"; }
paint() { circle "$1-active.xpm" "$2"; circle "$1-inactive.xpm" "$3"; circle "$1-prelight.xpm" "$4"; circle "$1-pressed.xpm" "$5"; }
paint close    '#ff5f57' '#4a4a4c' '#ff7b73' '#c9453e'
paint hide     '#febc2e' '#4a4a4c' '#ffd05c' '#c99824'
paint maximize '#28c840' '#4a4a4c' '#52d96a' '#1f9e33'
for st in active inactive prelight pressed; do cp "maximize-$st.xpm" "maximize-toggled-$st.xpm"; done
# тёмный заголовок и рамка
for f in *.xpm; do
  case "$f" in close-*|hide-*|maximize-*|shade-*|stick-*|menu-*) continue;; esac
  $IM "$f" -fill '#1c1c1e' -colorize 100 "xpm:$f"
done
sed -i '/^active_text_color=/d;/^inactive_text_color=/d' themerc
printf 'active_text_color=#ffffff\ninactive_text_color=#8e8e93\n' >> themerc
EOF
chmod +x config/hooks/live/0300-kobos-theme.hook.chroot

# --- Окно «Внешний вид»: палитра цветов для обоев, дока и заголовков, положение кнопок и дока ---
cat > config/includes.chroot/usr/local/bin/kobos-appearance <<'EOF'
#!/bin/bash
IM=$(command -v magick || command -v convert)
ID="identify"; command -v magick >/dev/null 2>&1 && ID="magick identify"

PALETTE=(
  "#1c1c1e|Чёрный"
  "#2c2c2e|Графит"
  "#0f1c3f|Тёмно-синий"
  "#0a84ff|Синий"
  "#0e5a63|Бирюзовый"
  "#1f4d3a|Зелёный"
  "#3a2a6b|Фиолетовый"
  "#c2457a|Розовый"
  "#5a1a2b|Бордовый"
  "#c25a1a|Оранжевый"
  "#8e8e93|Серый"
  "#f2f2f7|Белый"
)

# Выбор цвета: палитра или любой свой. Печатает #rrggbb
pick_color() {
  local args=() e sel out nums r g b
  for e in "${PALETTE[@]}"; do args+=("${e%%|*}" "${e#*|}"); done
  sel=$(zenity --list --title="$1" --text="Выберите цвет из палитры" \
    --column="Код" --column="Цвет" --hide-column=1 --print-column=1 \
    --width=340 --height=440 "${args[@]}" "custom" "Другой цвет…") || return 1
  if [ "$sel" = "custom" ]; then
    out=$(zenity --color-selection --show-palette --title="$1") || return 1
    case "$out" in
      \#*) echo "${out:0:7}";;
      *) nums=$(echo "$out" | tr -dc '0-9,'); IFS=, read -r r g b _ <<<"$nums"
         printf '#%02x%02x%02x\n' "$r" "$g" "$b";;
    esac
  else
    echo "$sel"
  fi
}

hex_r() { echo $((16#${1:1:2})); }
hex_g() { echo $((16#${1:3:2})); }
hex_b() { echo $((16#${1:5:2})); }
frac()  { awk -v v="$1" 'BEGIN{printf "%.4f", v/255}'; }

set_wallpaper() {   # $1 = #rrggbb
  local r g b m base
  r=$(frac "$(hex_r "$1")"); g=$(frac "$(hex_g "$1")"); b=$(frac "$(hex_b "$1")")
  for m in monitor0 $(xrandr --query 2>/dev/null | awk '/ connected/{print "monitor" $1}'); do
    base="/backdrop/screen0/$m/workspace0"
    xfconf-query -c xfce4-desktop -p "$base/image-style" -n -t int -s 0
    xfconf-query -c xfce4-desktop -p "$base/color-style" -n -t int -s 0
    xfconf-query -c xfce4-desktop -p "$base/rgba1" -n -t double -s "$r" -t double -s "$g" -t double -s "$b" -t double -s 1
  done
}

set_dock_color() {  # $1 = #rrggbb
  local name dir base d
  base=/usr/share/plank/themes/Default/dock.theme
  [ -f "$base" ] || { zenity --error --text="Не найдена тема дока."; return 1; }
  name="KOBos-$(date +%s)"
  dir="$HOME/.local/share/plank/themes/$name"
  mkdir -p "$dir"
  sed -e "s/^FillStartColor=.*/FillStartColor=$(hex_r "$1");;$(hex_g "$1");;$(hex_b "$1");;215/" \
      -e "s/^FillEndColor=.*/FillEndColor=$(hex_r "$1");;$(hex_g "$1");;$(hex_b "$1");;215/" \
      "$base" > "$dir/dock.theme"
  dconf write /net/launchpad/plank/docks/dock1/theme "'$name'"
  for d in "$HOME"/.local/share/plank/themes/KOBos-*; do [ "$d" = "$dir" ] || rm -rf "$d"; done
}

set_titlebar_color() {  # $1 = #rrggbb
  local cur new dst f
  cur=$(xfconf-query -c xfwm4 -p /general/theme 2>/dev/null)
  if [ "$cur" = "KOBos-Custom-A" ]; then new="KOBos-Custom-B"; else new="KOBos-Custom-A"; fi
  [ -d /usr/share/themes/KOBos-Mac/xfwm4 ] || { zenity --error --text="Тема окон не найдена."; return 1; }
  dst="$HOME/.themes/$new/xfwm4"
  rm -rf "$HOME/.themes/$new"; mkdir -p "$dst"
  cp -a /usr/share/themes/KOBos-Mac/xfwm4/. "$dst/"
  cd "$dst" || return 1
  for f in *.xpm; do
    case "$f" in close-*|hide-*|maximize-*|shade-*|stick-*|menu-*) continue;; esac
    $IM "$f" -fill "$1" -colorize 100 "xpm:$f"
  done
  xfconf-query -c xfwm4 -p /general/theme -n -t string -s "$new"
}

set_buttons() { xfconf-query -c xfwm4 -p /general/button_layout -n -t string -s "$1"; }
set_dock_position() { dconf write /net/launchpad/plank/docks/dock1/position "'$1'"; }

apply_defaults() {
  mkdir -p "$HOME/.config/kobos"
  [ -f "$HOME/.config/kobos/appearance-done" ] && return 0
  xfconf-query -c xfwm4 -p /general/theme -n -t string -s "KOBos-Mac"
  xfconf-query -c xfwm4 -p /general/title_alignment -n -t string -s "center"
  set_buttons "CHM|"
  xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "Adwaita-dark"
  set_wallpaper "#0f1c3f"
  set_dock_position bottom
  touch "$HOME/.config/kobos/appearance-done"
}

if [ "$1" = "--defaults" ]; then apply_defaults; exit 0; fi

while true; do
  act=$(zenity --list --title="Внешний вид KOBos" --text="Что изменить?" \
    --column="id" --column="Пункт" --hide-column=1 --print-column=1 --width=400 --height=400 \
    wall  "Цвет рабочего стола (обои)" \
    dock  "Цвет дока" \
    title "Цвет заголовков окон" \
    btnL  "Кнопки окон слева (как в macOS)" \
    btnR  "Кнопки окон справа (как в Windows)" \
    posB  "Док снизу" \
    posL  "Док слева" \
    posR  "Док справа") || exit 0
  case "$act" in
    wall)  c=$(pick_color "Цвет рабочего стола") && set_wallpaper "$c";;
    dock)  c=$(pick_color "Цвет дока") && set_dock_color "$c";;
    title) c=$(pick_color "Цвет заголовков окон") && set_titlebar_color "$c";;
    btnL)  set_buttons "CHM|";;
    btnR)  set_buttons "|HMC";;
    posB)  set_dock_position bottom;;
    posL)  set_dock_position left;;
    posR)  set_dock_position right;;
  esac
done
EOF
chmod +x config/includes.chroot/usr/local/bin/kobos-appearance

cat > config/includes.chroot/usr/share/applications/kobos-appearance.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Внешний вид
Exec=kobos-appearance
Icon=preferences-desktop-theme
Terminal=false
Categories=Settings;
EOF

# Первый вход: применить тему окон, цвет обоев и положение дока (один раз)
cat > config/includes.chroot/etc/skel/.config/autostart/kobos-appearance-first.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=KOBos внешний вид (первый запуск)
Exec=sh -c 'sleep 4; kobos-appearance --defaults'
X-GNOME-Autostart-enabled=true
EOF

# --- Steam и редактор учётной записи ставятся отдельным шагом: если что-то недоступно, сборка не падает ---
cat > config/hooks/live/0200-extras.hook.chroot <<'EOF'
#!/bin/sh
export DEBIAN_FRONTEND=noninteractive

# Steam из репозитория Debian (сам клиент докачивается при первом запуске)
echo "steam steam/question select I AGREE" | debconf-set-selections
echo "steam steam/license note" | debconf-set-selections
if dpkg --add-architecture i386 && apt-get update && \
   apt-get install -y steam-installer mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386; then
  echo "Steam установлен"
else
  echo "ВНИМАНИЕ: Steam не установился, пропускаю"
fi

# Учётная запись: редактор профиля (имя, аватар)
apt-get install -y mugshot || echo "ВНИМАНИЕ: mugshot недоступен, пропускаю"
EOF
chmod +x config/hooks/live/0200-extras.hook.chroot

echo "==> Список пакетов"
cat > config/package-lists/kobos.list.chroot <<'EOF'
# Рабочий стол
xfce4
xfce4-goodies
lightdm
lightdm-gtk-greeter
xdg-user-dirs
network-manager-gnome
pipewire
pipewire-pulse
wireplumber
pavucontrol
# Приложения
brave-browser
firefox-esr
libreoffice
vlc
gimp
thunar-archive-plugin
file-roller
evince
# Док, терминал, клавиатура, учётные записи
plank
xfce4-terminal
onboard
xfce4-xkb-plugin
lightdm-gtk-greeter-settings
accountsservice
blueman
# Внешний вид: цвета и темы
imagemagick
dconf-cli
x11-xserver-utils
gnome-themes-extra-data
# Языки: окно выбора, переводы, словари
zenity
libreoffice-l10n-ru
libreoffice-l10n-uk
libreoffice-l10n-de
firefox-esr-l10n-ru
firefox-esr-l10n-uk
firefox-esr-l10n-de
hunspell-ru
hunspell-uk
hunspell-de-de
hunspell-en-us
# Виджеты
conky-all
lm-sensors
xprintidle
pciutils
# Разработка
git
build-essential
python3
python3-pip
python3-venv
nodejs
npm
vim
nano
curl
ca-certificates
wget
htop
fastfetch
# Шрифты и язык
fonts-noto
fonts-noto-color-emoji
locales-all
# Установщик на диск
calamares
calamares-settings-debian
EOF

echo "==> Брендинг системы"
cat > config/hooks/live/0100-kobos.hook.chroot <<EOF
#!/bin/sh
set -e
echo "$HOST_NAME" > /etc/hostname
for alt in x-www-browser gnome-www-browser; do
  update-alternatives --set \$alt /usr/bin/brave-browser 2>/dev/null || true
done
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="$OS_NAME $OS_VERSION (на базе Debian)"/' /etc/os-release
cat > /etc/motd <<'M'

  Добро пожаловать в $OS_NAME $OS_VERSION!
  Система собрана на ядре Linux, основа - Debian.

M
EOF
chmod +x config/hooks/live/0100-kobos.hook.chroot

# Ярлык установщика на рабочем столе
cat > config/includes.chroot/etc/skel/Desktop/install-kobos.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Установить $OS_NAME на диск
Name[en]=Install $OS_NAME
Exec=sudo -E calamares
Icon=calamares
Terminal=false
Categories=System;
EOF
chmod +x config/includes.chroot/etc/skel/Desktop/install-kobos.desktop

cat > config/includes.chroot/etc/skel/Desktop/ЧИТАЙ-МЕНЯ.txt <<EOF
$OS_NAME $OS_VERSION
Чтобы установить систему на диск, запустите ярлык "Установить $OS_NAME на диск".
Логин в live-режиме: $LIVE_USER, пароль: live
EOF

echo "==> Сборка образа (это долго: 30-90 минут, нужен интернет и ~20 ГБ места)"
lb build 2>&1 | tee build.log

echo
echo "Готово:"
ls -lh ./*.iso

echo
echo "Проверка в виртуальной машине:"
echo "  qemu-system-x86_64 -m 4G -enable-kvm -cdrom $IMAGE_NAME-amd64.hybrid.iso -boot d"
