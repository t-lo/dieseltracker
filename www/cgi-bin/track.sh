#!/bin/bash

# Files

wwwdir=".."
datadir="$wwwdir/data"
prices_dir="$datadir/prices"
id_dir="$datadir/id"
current_list="$datadir/current"

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

    while read file; do
        echo -n "$file "
        tail -n1 "$prices_dir/$file"
    done < "$current_list" | sort -n -k4,4 -k 5,5 \
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
        <form action="track.sh" method="post" target="" >
            <button class="button" name="details" value="$id" type="submit">
EOF
        echo "$info" | awk '{ print "&euro; " $3 " (" $4 " km) <br /> "}'
        cut -f 3,5,6 "$id_dir/$id" 
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
    set terminal png size $graph_width,$graph_height enhanced transparent
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
        echo "    set multiplot" >>"$plot_cfg"
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

    > "$current_list"

    # fetch current data, put each record on a separate line, format for bash
    # variables
    curl -s \
        "http://www.spritpreismonitor.de/suche/?tx_spritpreismonitor_pi1%5BsearchRequest%5D%5BplzOrtGeo%5D=$plz&tx_spritpreismonitor_pi1%5BsearchRequest%5D%5Bumkreis%5D=$umkreis&tx_spritpreismonitor_pi1%5BsearchRequest%5D%5Bkraftstoffart%5D=diesel&tx_spritpreismonitor_pi1%5BsearchRequest%5D%5Btankstellenbetreiber%5D=" \
        | grep 'var spmResult' \
        | sed -e 's/.*\(\[.*\]\).*/\1/'  -e 's/[\[{]//g' -e 's/},/\n/g' \
              -e 's/}]//' -e 's/"\([^"]*\)":"\([^"]*\)",*/\1="\2" /g'   \
              -e 's/u00f6/\&ouml;/g' -e 's/u00df/\&szlig;/g'          \
              -e 's/u00fc/\&uuml;/g' -e 's/u00e4/\&auml;/g'          \
        | while read line; do
            eval "$line"

            local idfile="$id_dir/$mtsk_id"
            local pricefile="$prices_dir/${mtsk_id}"
            echo -e "$laengengrad\t$breitengrad\t$name\t$marke\t$strasse\t$hausnr\t$plz\t$ort\t$entfernung" > "$idfile"
            echo "$datum $diesel $entfernung ($ts)" >> "$pricefile"
            echo "$mtsk_id" >> "$current_list"
        done
    
    rm "$wwwdir/"*.png
}
# ----

function show_details() {
    local id="$1"
    local idfile="$id_dir/$id"

    if [ ! -f "$id_dir/$id" -o ! -f "$prices_dir/$id" ] ; then
        redirect
        return
    fi

    generate_plots "$id"

    local lon="`cut -f 1 $idfile`"
    local lat="`cut -f 2 $idfile`"

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
        cut -f 3- $idfile
    cat << EOF
        </div> 
EOF
        write_html_graphs "$id"

        echo '<br clear="all"/> <hr width="30%" height="2pt">'

        head -n 50 "$prices_dir/$id" | cut -d " " -f 1-3 | sed 's/$/<br \/>/'

cat << EOF
        <br clear="all" /> <hr width="30%" height="2pt">
        <form action="track.sh" method="get" >
            <button class="button" type="submit">Zur&uuml;ck</button> </form>

        <br clear="all"/>

        <div id="mapdiv" class="mapdiv" >&nbsp;</div>
          <script src="http://www.openlayers.org/api/OpenLayers.js"></script>
          <script>
            map = new OpenLayers.Map("mapdiv");
            map.addLayer(new OpenLayers.Layer.OSM());
         
            var lonLat = new OpenLayers.LonLat( $lon ,$lat )
                  .transform(
                    new OpenLayers.Projection("EPSG:4326"), // transform from WGS 1984
                    map.getProjectionObject() // to Spherical Mercator Projection
                  );
         
            var zoom=17;
         
            var markers = new OpenLayers.Layer.Markers( "Markers" );
            map.addLayer(markers);
         
            markers.addMarker(new OpenLayers.Marker(lonLat));
         
            map.setCenter (lonLat, zoom);
        </script>

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
