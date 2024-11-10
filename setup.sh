#!/bin/bash

cd $(dirname $0)

### Prepare build directory

workdir='/usr/local/var/gnome2remix.workdir'

mkdir -p $workdir
cp -r *  $workdir
cd       $workdir
rm *.tar*

### Check if distro is supported and install dependencies

if $(grep '^ID=' /etc/os-release | grep -q ubuntu)
then
  apt install -y $(cat deps_ubuntu)
elif $(grep '^ID=' /etc/os-release | grep -q debian)
then
  # Debian needs libunique to be installed manually
  apt install -y $(grep -v libunique deps_ubuntu)
  PATH=$PATH:/usr/sbin  # This is strange
  arch=$(dpkg --print-architecture)
  wget https://mirror.yandex.ru/debian/pool/main/libu/libunique/libunique-1.0-0_1.1.6-6_$arch.deb
  wget https://mirror.yandex.ru/debian/pool/main/libu/libunique/libunique-dev_1.1.6-6_$arch.deb
  dpkg -i libunique-1.0-0_1.1.6-6_$arch.deb libunique-dev_1.1.6-6_$arch.deb
  apt -y --fix-broken install
else
  echo "$(grep '^NAME=' /etc/os-release | sed 's/NAME=//' | tr -d '\"') is not supported. Exit."
  exit 1
fi

if [ $? -ne 0 ]
then
  echo 'Can not install required packages. Exit'
  exit 1
fi

### Helper function

prep()
{
  url=$(grep $1- sources)
  archive=$(basename $url)
  wget $url
  tar -xf $archive
  cd $(tar -tf $archive | head -n 1)
}

### Master function
### Usage: inst component ["configure_options"] ["compiler_options"]
inst()
{
  name=$1
  config_opts=""
  compile_opts=""

  for param in "$@"
    do
    if [ ! -z "$(echo $param | grep 'LIBS\|CXXFLAGS')" ]
    then
      compile_opts+="$param "
    elif [ ! -z "$(echo $param | grep '\-\-')" ]
    then
      config_opts+="$param "
    fi
  done

  # Continue from last stopped component
  last=$(tail -n 1 log | grep started | cut -d ' ' -f 1)
  if [ ! -z $last ] && [ $last != $name ]
  then
    echo "Skip successfully installed component $name"
    return
  fi

  echo "$name installation was started" >> $workdir/log

  prep $name
  if [ -d ../patches/$name ]
  then
    for pfile in $(ls ../patches/$name/*.patch)
    do
      patch -p1 -i $pfile
    done
  fi
  eval "$compile_opts"
  export LIBS CFLAGS CXXFLAGS
  eval "./configure $config_opts --disable-scrollkeeper"
  make &&  make install
  if [ $? -ne 0 ]
  then
    echo "$name was not installed due to error"
    exit 1
  else
    echo "$name was installed" >> $workdir/log
  fi
  ldconfig
  cd ..
}

### Install all components

inst libwnck
inst gnome-doc-utils
ln -s /usr/local/lib/python3/dist-packages/xml2po/ /usr/lib/python3/dist-packages/xml2po
inst ORBit2
inst GConf
inst libbonobo
inst gnome-mime-data
inst gnome-vfs --disable-openssl
inst libgnome
inst libbonoboui
inst libgweather
inst libgnomekbd
inst gnome-desktop
inst gnome-icon-theme
inst gnome-menus --disable-python
inst gnome-panel --enable-bonobo "LIBS='-lgmodule-2.0 -lm -lgdk-x11-2.0 -lcairo -lX11'"
inst nautilus "LIBS='-lgmodule-2.0'"
inst metacity
inst gnome-settings-daemon
inst gnome-control-center "LIBS='-lgmodule-2.0'"
inst gnome-terminal
inst gnome-system-monitor "CXXFLAGS='-std=c++11 -g -O2' LIBS='-lgmodule-2.0'"
inst gtksourceview
inst gedit "--disable-spell --disable-python" "LIBS='-lgmodule-2.0 -lICE'"
inst eog "LIBS='-lgmodule-2.0'"
inst evince "--without-keyring --disable-tests" "LIBS='-lICE'"
inst file-roller
inst gcalctool --with-gtk=2.0

### Create empty file to pass gnome-session configure
touch    /usr/local/bin/gconf-sanity-check-2
chmod +x /usr/local/bin/gconf-sanity-check-2
inst gnome-session
rm /usr/local/bin/gconf-sanity-check-2

### No need for all utils except for gnome-screenshot
prep gnome-utils
patch -p1 -i ../patches/gnome-utils/configure.patch
./configure
cd gnome-screenshot
make && make install
cd ../../

### No need for all bunch of themes since package gtk2-engines already has most of it.
### But metacity requires fallback Clearlooks theme to be installed system-wide in
### /usr/share/themes since system gtk2 don't see themes in /usr/local.
prep gnome-themes
mkdir -p /usr/share/themes/Clearlooks/metacity-1
cp metacity-themes/Clearlooks/metacity-theme-1.xml /usr/share/themes/Clearlooks/metacity-1
cp desktop-themes/Clearlooks/index.theme /usr/share/themes/Clearlooks/

### Also Mist icons theme looks good with Clearlooks so install it
./configure
cd icon-themes/Mist/
make && make install
cd ../../../

### Rename gnome-session to gnome2-session to prevent collisions with GNOME>=3
mv /usr/local/bin/gnome-session /usr/local/bin/gnome2-session

### Remake desktop file and place it to /usr/etc since some display managers
### (e.g. LightDM) do not look into /usr/local/etc
rm /usr/local/share/xsessions/gnome.desktop
mkdir -p /usr/share/xsessions/
echo '[Desktop Entry]
Name=GNOME 2
Exec=env XDG_CONFIG_DIRS=/etc/xdg:/usr/local/etc/xdg /usr/local/bin/gnome2-session
Type=Application' > /usr/share/xsessions/gnome2.desktop

### Add autostart file for polkit-gnome-agent to be able to mount filesystems in nautilus
echo "[Desktop Entry]
Name=PolicyKit Authentication Agent for GNOME 2
$(grep '^Exec\|^Terminal\|^Type\|^NoDisplay' /etc/xdg/autostart/polkit-gnome-authentication-agent-1.desktop)
OnlyShowIn=GNOME;" > /usr/local/etc/xdg/autostart/polkit-gnome2-authentication-agent.desktop

### Make evince and gnome-control-center visible in main menu
sed '/NoDisplay=true/d' -i /usr/local/share/applications/evince.desktop \
			   /usr/local/share/applications/gnomecc.desktop

### While default nm-applet do not autostart in GNOME, change it
sed 's/NotShowIn=KDE;/OnlyShowIn=/' /etc/xdg/autostart/nm-applet.desktop > \
                                    /usr/local/etc/xdg/autostart/nm-applet-gnome2.desktop

echo Yay! GNOME 2.32 was successfully installed!
exit 0
