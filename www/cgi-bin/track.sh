#!/bin/bash

# Files

wwwdir=".."
datadir="$wwwdir/data"
prices_dir="$datadir/prices"
id_dir="$datadir/id"

plz=10827
umkreis=5 #km

graph_width=900
graph_height=300

function write_html_graphs() {
    local id="$1"
    if [ "$id" != "" ]; then
        local day="${id}-day"
        local week="${id}-week"
        local month="${id}-month"
    else
        local day="day"
        local week="week"
        local month="month"
    fi
cat << EOF
        <br clear="all" />

        <canvas id="$day" width="$graph_width" height="$graph_height" > </canvas>
        <br /> <hr width="30%">
        <canvas id="$week" width="$graph_width" height="$graph_height" ></canvas>
        <br /> <hr width="30%">
        <canvas id="$month" width="$graph_width" height="$graph_height" ></canvas>

    <script type="text/javascript">
      function load_image(name) {
        var canvas = document.getElementById(name);
        var ctx = canvas.getContext('2d');
        var image = new Image();
        image.onload = function() { ctx.drawImage(image,0,0); }
        image.src = "../" + name + ".png?$RANDOM"
      }
      function load_images() {
        var il = ["$day", "$week", "$month"]
        for (var i in il) { load_image(il[i]) }
      }
      setTimeout(load_images, 100)
    </script>
EOF
}
# ----

function write_html() {

    local sorted="`mktemp`"

    for file in "$prices_dir/"*; do
        echo -n "`basename $file` "
        tail -n1 $file
    done | sort -n -k4,4 -k 5,5 \
    > "$sorted"

    echo -en 'content-type:text/html; charset=utf-8\r\n\r\n'
    cat << EOF
<html>
    <head>
        <link rel="stylesheet" type="text/css" href="../index.css">
    </head>
    <body>
	<center>

        <div class="titlebar" height="5%">
            <h1 style="margin-left: 5pt;"> Spritpreise </h1>
        </div> 
EOF

    write_html_graphs

    echo '<br clear="all"/>'

    while read id info; do
        cat << EOF
        <form action="track.sh" method="post" >
            <button class="button" name="details" value="$id" type="submit">
EOF
        echo "$info" | cut -d " " -f3,6-
        cat "$id_dir/$id"
        echo '</button></form>'
    done < "$sorted"

    echo '</body></html>'
    rm "$sorted"
}
# ----

function redirect() {
    echo -en 'content-type:text/html; charset=utf-8\r\n\r\n'
    echo '
        <html>
        <head>
        <META HTTP-EQUIV=Refresh CONTENT="0; URL=track.sh">
        </head>
        </html>
        '
}
# ----

function plot() {
    local from="$1"
    local to="$2"
    local single_day="$3"
    local plot_name="$4"
    local desc="$5"
    local id="$6"

    local xtics=""
    local mxtics=""
    [    "$single_day" = "true" ] && {
        xtics="set xtics 0,7200"
      }

    local plot_cfg=`mktemp`

    cat >"$plot_cfg" << EOF
    set terminal png size $graph_width,$graph_height enhanced transparent font helvetica 15
    set output '$plot_name.png'

    set title "$desc"
    set style data fsteps
    set xdata time
    set timefmt "%Y-%m-%d %H:%M:%S"
    set xrange [ "$from" : "$to" ]
    set yrange [ 1.2 : 1.6 ]
    set ytics 0.1
    set format x "%H:%M\\n%a %d"
    $xtics
    set mxtics 2
    set grid xtics mxtics ytics
    set key left
    set lmargin 10
    set bmargin 3
    set tmargin 3
EOF
    if [ -f "$prices_dir/$id" ] ; then
        echo "    plot '$prices_dir/$id' using 1:3 index 0 t \"\" with lines" >>"$plot_cfg"
    else
        echo "    set multiplot enhanced" >>"$plot_cfg"
        local onlyonce="1"
        for file in "$prices_dir/"*; do
            echo "    plot '$file' using 1:3 index 0 t \"\" with lines" >>"$plot_cfg"
            [ "$onlyonce" = "1" ] && {
                echo "    set xtics format \"\"" >> "$plot_cfg"
                echo "    set ytics format \"\"" >> "$plot_cfg"
                echo "    set title \"\"" >> "$plot_cfg"
                onlyonce="0"
            }
        done
        echo "    unset multiplot" >>"$plot_cfg"
    fi

    gnuplot "$plot_cfg"
    rm "$plot_cfg"
}
# ----

function generate_plots() {
    local id="$1"

    local today="`date --rfc-3339=seconds  -d 0 | sed 's/\+.*//'`"
    local tomorrow="`date --rfc-3339=seconds -d \"+1day 0\" | sed 's/\+.*//'`"
    local last_week="`date --rfc-3339=seconds -d \"-7day 0\" | sed 's/\+.*//'`"
    local last_month="`date --rfc-3339=seconds -d \"-30day 0\" | sed 's/\+.*//'`"

    if [ "$id" != "" ]; then
        local day="$wwwdir/${id}-day"
        local week="$wwwdir/${id}-week"
        local month="$wwwdir/${id}-month"
    else
        local day="$wwwdir/day"
        local week="$wwwdir/week"
        local month="$wwwdir/month"
    fi

    plot "$today" "$tomorrow" "true" "$day" "Heute" "$id"
    plot "$last_week" "$tomorrow" "false" "$week" "Letzte Woche" "$id"
    plot "$last_month" "$tomorrow" "false" "$month" "Letzter Monat" "$id"
}
# ----

function fetch_and_update_data() {
    local ts="`date +%D-%H:%M:%S`"
    
    mkdir -p "$datadir"
    mkdir -p "$prices_dir"
    mkdir -p "$id_dir"

    # fetch current data, put each record on a separate line, format for bash
    # variables
    curl -s \
        "http://www.spritpreismonitor.de/suche/?tx_spritpreismonitor_pi1%5BsearchRequest%5D%5BplzOrtGeo%5D=$plz&tx_spritpreismonitor_pi1%5BsearchRequest%5D%5Bumkreis%5D=$umkreis&tx_spritpreismonitor_pi1%5BsearchRequest%5D%5Bkraftstoffart%5D=diesel&tx_spritpreismonitor_pi1%5BsearchRequest%5D%5Btankstellenbetreiber%5D=" \
        | grep 'var spmResult' \
        | sed -e 's/.*\(\[.*\]\).*/\1/'  -e 's/[\[{]//g' -e 's/},/\n/g' \
              -e 's/}]//' -e 's/"\([^"]*\)":"\([^"]*\)",*/\1="\2" /g' \
        | while read line; do
            eval "$line"

            local idfile="$id_dir/$mtsk_id"
            local pricefile="$prices_dir/${mtsk_id}"
            [ ! -f "$idfile" ] && \
                echo "$name ($marke) $strasse $hausnr $plz $ort ($entfernung km)" > "$idfile"
            echo "$datum $diesel $entfernung ($ts)" >> "$pricefile"
        done
    
    rm "$wwwdir/"*.png
}
# ----

function show_details() {
    local id="$1"

    if [ ! -f "$id_dir/$id" -o ! -f "$prices_dir/$id" ] ; then
        redirect
        return
    fi

    generate_plots "$id"

    echo -en 'content-type:text/html; charset=utf-8\r\n\r\n'
    cat << EOF
<html>
    <head>
        <link rel="stylesheet" type="text/css" href="../index.css">
    </head>
    <body>
	<center>

        <div class="titlebar" height="5%">
            <h1 style="margin-left: 5pt;"> 
EOF
        cat "$id_dir/$id"
    cat << EOF
        </div> 
        <br clear="all"/>
EOF
        write_html_graphs "$id"

        echo '<br clear="all"/>'

        cat "$prices_dir/$id" | cut -d " " -f 1-3 | sed 's/$/<br \/>/'

cat << EOF
        <br clear="all" />

</body></html> 
EOF

}

#
# MAIN
#
cd `dirname $0`

cmd="$1"
if [ "$REQUEST_METHOD" = "POST" ] && [ "$CONTENT_LENGTH" -gt 0 ] ; then
    read -n $CONTENT_LENGTH -r data
    cmd=`echo "$data" | cut -d '=' -f 1`
    val=`echo "$data" | cut -d '=' -f 2`
fi

if [ "$cmd" != "" ] ; then
    case "$cmd" in
        update) fetch_and_update_data; generate_plots; redirect;;
        details) show_details "$val";;
        *) redirect;;
    esac
else
    write_html
fi
