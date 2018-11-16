#!/usr/bin/env bash

rm -R src tmp dest

mkdir -p src/
mkdir -p tmp/
mkdir -p dest/

curl 'https://www2.census.gov/geo/tiger/GENZ2014/shp/cb_2014_06_tract_500k.zip' -o src/cb_2014_06_tract_500k.zip
curl 'https://api.census.gov/data/2014/acs5?get=B01003_001E&for=tract:*&in=state:06' -o src/cb_2014_06_tract_B01003.json

unzip -o src/cb_2014_06_tract_500k.zip -d src/

shp2json src/cb_2014_06_tract_500k.shp -o tmp/ca.json

ndjson-split 'd.features' \
  < tmp/ca.json \
  > tmp/ca.ndjson

grep -Rrih '"COUNTYFP":"075"' tmp/ca.ndjson >> tmp/sf.ndjson

ndjson-reduce 'p.features.push(d), p' '{type: "FeatureCollection", features: []}' \
  < tmp/sf.ndjson \
  > tmp/sf.json

geoproject 'd3.geoConicEqualArea().parallels([34, 40.5]).rotate([120, 0]).fitSize([700,350], d)' < tmp/sf.json > tmp/sf-albers.json

geo2svg -w 700 -h 350 < tmp/sf-albers.json > dest/sf-albers.svg

ndjson-split 'd.features' \
  < tmp/sf-albers.json \
  > tmp/sf-albers.ndjson

ndjson-map 'd.id = d.properties.GEOID.slice(2), d' \
  < tmp/sf-albers.ndjson \
  > tmp/sf-albers-id.ndjson


ndjson-cat src/cb_2014_06_tract_B01003.json \
  | ndjson-split 'd.slice(1)' \
  | ndjson-map '{id: d[2] + d[3], B01003: +d[0]}' \
  > tmp/cb_2014_06_tract_B01003.ndjson

## Set all population values of tracts outside of San Fransico to 0
# while IFS='' read -r line || [[ -n "$line" ]]; do
#   if [[ "$line" =~ '{"id":"075' ]] ; then
#     echo $line >> tmp/sf_2014_B01003.ndjson
#   else
#     echo "$(echo $line | cut -d":" -f"1,2"):0}" >> tmp/sf_2014_B01003.ndjson
#   fi
# done < tmp/cb_2014_06_tract_B01003.ndjson

ndjson-join 'd.id' \
  tmp/sf-albers-id.ndjson \
  tmp/cb_2014_06_tract_B01003.ndjson \
  > tmp/sf-albers-join.ndjson

ndjson-map 'd[0].properties = {density: Math.floor(d[1].B01003 / d[0].properties.ALAND * 2589975.2356)}, d[0]' \
  < tmp/sf-albers-join.ndjson \
  > tmp/sf-albers-density.ndjson

ndjson-reduce 'p.features.push(d), p' '{type: "FeatureCollection", features: []}' \
  < tmp/sf-albers-density.ndjson \
  > tmp/sf-albers-density.json

ndjson-map -r d3 \
  '(d.properties.fill = d3.scaleSequential(d3.interpolateViridis).domain([0, 12391])(d.properties.density), d)' \
  < tmp/sf-albers-density.ndjson \
  > tmp/sf-albers-color.ndjson

geo2svg -n --stroke none -p 1 -w 700 -h 350 \
  < tmp/sf-albers-color.ndjson \
  > dest/sf-albers-color.svg

geo2topo -n \
  tracts=tmp/sf-albers-color.ndjson \
  > tmp/sf-tracts-topo.json

toposimplify -p 1 -f \
  < tmp/sf-tracts-topo.json \
  > tmp/sf-simple-topo.json

topoquantize 1e5 \
  < tmp/sf-simple-topo.json \
  > tmp/sf-quantized-topo.json

topomerge -k 'd.id.slice(0, 3)' counties=tracts \
  < tmp/sf-quantized-topo.json \
  > tmp/sf-merge-topo.json

topomerge --mesh -f 'a !== b' counties=counties \
  < tmp/sf-merge-topo.json \
  > tmp/sf-topo.json

topo2geo tracts=- \
  < tmp/sf-topo.json \
  | ndjson-map -r d3 'z = d3.scaleSequential(d3.interpolateViridis).domain([0, 12391]), d.features.forEach(f => f.properties.fill = z(f.properties.density)), d' \
  | ndjson-split 'd.features' \
  | geo2svg -n --stroke none -p 1 -w 700 -h 350 \
  > dest/sf-tracts-color.svg

topo2geo tracts=- \
  < tmp/sf-topo.json \
  | ndjson-map -r d3 'z = d3.scaleSequential(d3.interpolateViridis).domain([0, 100]), d.features.forEach(f => f.properties.fill = z(Math.sqrt(f.properties.density))), d' \
  | ndjson-split 'd.features' \
  | geo2svg -n --stroke none -p 1 -w 700 -h 350 \
  > dest/sf-tracts-sqrt.svg

topo2geo tracts=- \
  < tmp/sf-topo.json \
  | ndjson-map -r d3 'z = d3.scaleLog().domain(d3.extent(d.features.filter(f => f.properties.density), f => f.properties.density)).interpolate(() => d3.interpolateViridis), d.features.forEach(f => f.properties.fill = z(f.properties.density)), d' \
  | ndjson-split 'd.features' \
  | geo2svg -n --stroke none -p 1 -w 700 -h 350 \
  > dest/sf-tracts-log.svg

topo2geo tracts=- \
  < tmp/sf-topo.json \
  | ndjson-map -r d3 'z = d3.scaleQuantile().domain(d.features.map(f => f.properties.density)).range(d3.quantize(d3.interpolateViridis, 256)), d.features.forEach(f => f.properties.fill = z(f.properties.density)), d' \
  | ndjson-split 'd.features' \
  | geo2svg -n --stroke none -p 1 -w 700 -h 350 \
  > dest/sf-tracts-quantile.svg

topo2geo tracts=- \
  < tmp/sf-topo.json \
  | ndjson-map -r d3 -r d3=d3-scale-chromatic 'z = d3.scaleThreshold().domain([0, 1547, 3232, 4474, 5927, 7867, 12391]).range(d3.schemeOrRd[7]), d.features.forEach(f => f.properties.fill = z(f.properties.density)), d' \
  | ndjson-split 'd.features' \
  | geo2svg -n --stroke none -p 1 -w 700 -h 350 \
  > dest/sf-tracts-threshold.svg

(topo2geo tracts=- \
    < tmp/sf-topo.json \
    | ndjson-map -r d3 -r d3=d3-scale-chromatic 'z = d3.scaleThreshold().domain([0, 1547, 3232, 4474, 5927, 7867, 12391]).range(d3.schemeOrRd[7]), d.features.forEach(f => f.properties.fill = z(f.properties.density)), d' \
    | ndjson-split 'd.features'; \
topo2geo counties=- \
    < tmp/sf-topo.json \
    | ndjson-map 'd.properties = {"stroke": "#000", "stroke-opacity": 0.3}, d')\
<<<<<<< HEAD:density-choropleth.sh
  | geo2svg -n --stroke none -p 1 -w 700 -h 350 \
  > dest/sf.svg
=======
  | geo2svg -n --stroke none -p 1 -w 960 -h 960 \
  > dest/sf.svg
>>>>>>> e87e1b9c23dbf69a34967fa0a6a9ffe84e8ce32e:density-choropleth.sh
