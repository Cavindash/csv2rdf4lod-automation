#!/bin/bash
#
#   Copyright 2012 Timothy Lebo
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# Usage:
#
# Notes:
#   (vload usage: vload [rdf|ttl|nt|nq] [data_file] [graph_uri])

usage_message="usage: `basename $0` [-n] url [-ng named_graph]" 

if [[ "$1" == "--help" || $# -lt 1 ]]; then
   echo $usage_message 
   echo "  -n  : dry run - do not download or load into named graph."
   echo "  url : the URL to retrieve and load into a named graph."
   echo "  -ng : the named graph to place 'url'. (if not provided, -ng == 'url')."
   echo "  (setting env var CSV2RDF4LOD_CONVERT_DEBUG_LEVEL=finest will leave temporary files after invocation.)"
   exit 1
fi

see='https://github.com/timrdf/csv2rdf4lod-automation/wiki/CSV2RDF4LOD-not-set'
CSV2RDF4LOD_HOME=${CSV2RDF4LOD_HOME:?"not set; source csv2rdf4lod/source-me.sh or see $see"}
CSV2RDF4LOD_BASE_URI=${CSV2RDF4LOD_BASE_URI:?"not set; source csv2rdf4lod/source-me.sh or see $see"}

export PATH=$PATH`$CSV2RDF4LOD_HOME/bin/util/cr-situate-paths.sh`
export CLASSPATH=$CLASSPATH`$CSV2RDF4LOD_HOME/bin/util/cr-situate-classpaths.sh`

dryrun="false"
if [ $1 == "-n" ]; then
   dryrun="true"; shift 
fi

PROV_BASE="http://www.provenanceweb.net/id/"
PROV_BASE="$CSV2RDF4LOD_BASE_URI/id/"

# MD5 this script
curlMD5="md5_`$CSV2RDF4LOD_HOME/bin/util/md5.sh \`which curl\``"

# MD5 this script
myMD5="md5_`$CSV2RDF4LOD_HOME/bin/util/md5.sh $0`"

TEMP="_"`basename $0``date +%s`_$$.response

escapedEndpoint=`echo ${CSV2RDF4LOD_PUBLISH_VIRTUOSO_SPARQL_ENDPOINT} | perl -e 'use URI::Escape; @userinput = <STDIN>; foreach (@userinput) { chomp($_); print uri_escape($_); }'`

logID=`resource-name.sh`
while [ $# -gt 0 ]; do
   echo
   echo "/////------------------------------ `basename $0` ------------------------------\\\\\\\\\\"

   url="$1"
   requestID=`resource-name.sh`

   #
   # Grab the file.
   #
   if [ "$dryrun" != "true" ]; then
      $CSV2RDF4LOD_HOME/bin/util/pcurl.sh $url -n $TEMP     # Side affect: creates $TEMP.pml.ttl (will be loaded below).
      unzipped=""
      gunzip -t $TEMP &> /dev/null
      if [ $? -eq 0 ]; then
         unzipped=".unzipped"
         echo "INFO: `basename $0`: HTTP response was compressed; uncompressing."
         gunzip -c $TEMP > ${TEMP}${unzipped}
      fi
   else
      echo `basename $CSV2RDF4LOD_HOME/bin/util/pcurl.sh` $url -n $TEMP
      echo "<http://www.w3.org/2002/07/owl#sameAs> <http://www.w3.org/2002/07/owl#sameAs> <http://www.w3.org/2002/07/owl#sameAs> ." > $TEMP
   fi
   usageDateTime=`$CSV2RDF4LOD_HOME/bin/util/dateInXSDDateTime.sh`
   usageDateTimeSlug=`$CSV2RDF4LOD_HOME/bin/util/dateInXSDDateTime.sh coin:slug`

   #echo "PVLOAD: url                $url"
   flag=$2
   if [ "$flag" == "-ng" -a $# -ge 2 ]; then # Override the default named graph name (the URL of the source).
      named_graph="$3"
      #echo "PVLOAD: -ng             $named_graph"; 
      shift 2
   elif [ "$flag" == "-ng" -a $# -lt 2 ]; then
      echo "ERROR: -ng given with no value."
      exit 1
   else
      named_graph="$url"                          # Default to a named graph name of the URL source.
   fi
   echo "INFO: `basename $0`: (URL) $url"
   echo "                   --> (Named Graph) $named_graph"

   #
   # Normalize into ntriples (note, this step is not worth describing in the provenance).
   # (because Virtuoso chokes on some well-formatted Turtle, and they don't respond to bugs).
   #
   #echo guessing `$CSV2RDF4LOD_HOME/bin/util/guess-syntax.sh $url rapper`
   syntax=`$CSV2RDF4LOD_HOME/bin/util/guess-syntax.sh $url rapper`
   liked_guess=$? # 0 : liked its guess, 1: did NOT like its guess
   if [[ $liked_guess == 1 ]]; then
      #echo "DIDN'T LIKED SYNTAX GUESS $syntax: $liked_guess"
      syntax=`$CSV2RDF4LOD_HOME/bin/util/guess-syntax.sh --inspect ${TEMP}${unzipped} rapper`
      echo "INFO: Guess by inspection: $syntax"
   else
      echo "INFO: Guessing syntax without inspection: $syntax ($url)"
   fi

   # Turtle to N-TRIPLES (b/c Virtuoso chokes on some Turtle and we need to spoon feed).
   too_big="no"
   for file in `find . -size +1900M -name ${TEMP}${unzipped}`; do 
      too_big="yes"; 
      echo "${TEMP}${unzipped} exceeds 1900MB, chunking."; 
      rm cHuNk* &> /dev/null
      $CSV2RDF4LOD_HOME/bin/split_ttl.pl ${TEMP}${unzipped}
      for chunk in cHuNk*; do
         rapper -q $syntax -o ntriples $chunk >> ${TEMP}${unzipped}.nt
         #debug wc -l ${TEMP}${unzipped}.nt
      done
      rm cHuNk*
   done
   if [ $too_big == "no" ]; then
      rapper -q $syntax -o ntriples ${TEMP}${unzipped} > ${TEMP}${unzipped}.nt
   fi

   if [ "$CSV2RDF4LOD_CONVERT_DEBUG_LEVEL" != "finest" ]; then
      rm $TEMP
   fi

   if [ `wc -l ${TEMP}${unzipped}.nt | awk '{print $1}'` -gt 0 ]; then
      # Relative paths.
      sourceUsage="sourceUsage$requestID"
      escapedNG=`echo $named_graph | perl -e 'use URI::Escape; @userinput = <STDIN>; foreach (@userinput) { chomp($_); print uri_escape($_); }'`
      # see https://github.com/timrdf/csv2rdf4lod-automation/wiki/Naming-sparql-service-description's-sd:NamedGraph
      named_graph_global="${CSV2RDF4LOD_PUBLISH_VIRTUOSO_SPARQL_ENDPOINT}?query=PREFIX%20sd%3A%20%3Chttp%3A%2F%2Fwww.w3.org%2Fns%2Fsparql-service-description%23%3E%20CONSTRUCT%20%7B%20%3Fendpoints_named_graph%20%3Fp%20%3Fo%20%7D%20WHERE%20%7B%20GRAPH%20%3C${escapedNG}%3E%20%7B%20%5B%5D%20sd%3Aurl%20%3C${escapedEndpoint}%3E%3B%20sd%3AdefaultDatasetDescription%20%5B%20sd%3AnamedGraph%20%3Fendpoints_named_graph%20%5D%20.%20%3Fendpoints_named_graph%20sd%3Aname%20%3C${escapedNG}%3E%3B%20%3Fp%20%3Fo%20.%20%7D%20%7D"

      xsl="-xsl:$CSV2RDF4LOD_HOME/bin/util/pvload-latest-ng-load.xsl"
      noop="-s:$CSV2RDF4LOD_HOME/bin/util/pvload-latest-ng-load.xsl"
      java_saxon="java -cp $CLASSPATH:$CSV2RDF4LOD_HOME/bin/dup/saxonb9-1-0-8j.jar net.sf.saxon.Transform $xsl $noop"
      latest_NG_nodeset=`$java_saxon endpoint=${CSV2RDF4LOD_PUBLISH_VIRTUOSO_SPARQL_ENDPOINT} named-graph=${named_graph}` 
      # pvload-latest-ng-load.xsl can call vsr:endpoint for a generic call, but it needs to not be dumb about its caching.
      if [ ${#latest_NG_nodeset} -gt 0 ]; then
         echo "INFO: `basename $0` found provenance of previous named graph load: $latest_NG_nodeset"
         latest_NG_nodeset="<$latest_NG_nodeset>"
      fi

      echo
      echo "@prefix xsd:        <http://www.w3.org/2001/XMLSchema#> ."                                          > ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix rdfs:       <http://www.w3.org/2000/01/rdf-schema#> ."                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix dcterms:    <http://purl.org/dc/terms/> ."                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix sioc:       <http://rdfs.org/sioc/ns#> ."                                                  >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix skos:       <http://www.w3.org/2004/02/skos/core#> ."                                      >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix pmlp:       <http://inference-web.org/2.0/pml-provenance.owl#> ."                          >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix pmlj:       <http://inference-web.org/2.0/pml-justification.owl#> ."                       >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix foaf:       <http://xmlns.com/foaf/0.1/> ."                                                >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix sd:         <http://www.w3.org/ns/sparql-service-description#> ."                          >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix oboro:      <http://obofoundry.org/ro/ro.owl#> ."                                          >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix oprov:      <http://openprovenance.org/ontology#> ."                                       >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix hartigprov: <http://purl.org/net/provenance/ns#> ."                                        >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix prov:       <http://www.w3.org/ns/prov#> ."                                                >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix dcat:       <http://www.w3.org/ns/dcat#> ."                                                >> ${TEMP}${unzipped}.load.pml.ttl
      echo "@prefix conversion: <http://purl.org/twc/vocab/conversion/> ."                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      $CSV2RDF4LOD_HOME/bin/util/user-account.sh                                                               >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<$url>"                                                                                            >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   a pmlp:Source;"                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${CSV2RDF4LOD_PUBLISH_VIRTUOSO_SPARQL_ENDPOINT}>"                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   a pmlp:InferenceEngine, pmlp:WebService;"                                                       >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${PROV_BASE}nodeSet${requestID}>"                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   a pmlj:NodeSet;"                                                                                >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   pmlp:hasCreationDateTime \"${usageDateTime}\"^^xsd:dateTime; # deprecate"                       >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   dcterms:created          \"${usageDateTime}\"^^xsd:dateTime;"                                   >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   pmlj:hasConclusion <${named_graph_global}#${usageDateTimeSlug}>;"                               >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   pmlj:isConsequentOf <${PROV_BASE}infStep${requestID}>;"                                         >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${named_graph_global}#${usageDateTimeSlug}> skos:broader <${named_graph_global}> ."               >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${PROV_BASE}infStep${requestID}>"                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   a pmlj:InferenceStep;"                                                                          >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   pmlj:hasAntecedentList ( $latest_NG_nodeset "                                                   >> ${TEMP}${unzipped}.load.pml.ttl
      echo "                            [ a pmlj:NodeSet; pmlj:hasConclusion <$url>; ] );"                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   pmlj:hasInferenceEngine [ a conversion:TripleStore ];"                                          >> ${TEMP}${unzipped}.load.pml.ttl
      #echo "   pmlj:hasInferenceRule <http://inference-web.org/registry/MPR/TRIPLE_STORE_LOAD.owl#>;"         >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   pmlj:hasInferenceRule <http://inference-web.org/registry/MPR/RDFModelUnion.owl#RDFModelUnion>;" >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   oboro:has_agent          `$CSV2RDF4LOD_HOME/bin/util/user-account.sh --cite`;"                  >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   hartigprov:involvedActor `$CSV2RDF4LOD_HOME/bin/util/user-account.sh --cite`;"                  >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   dcterms:date \"`$CSV2RDF4LOD_HOME/bin/util/dateInXSDDateTime.sh`\"^^xsd:dateTime;"              >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl

      #
      # The above is PML. Below is PROV-O
      #
      echo "# PROV-O is better than PML 2: "                                                                   >> ${TEMP}${unzipped}.load.pml.ttl

      echo "<$url>"                                                                                            >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   a foaf:Document;"                                                                               >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${named_graph_global}#${usageDateTimeSlug}>"                                                      >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   a sd:NamedGraph;"                                                                               >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   dcterms:created      \"${usageDateTime}\"^^xsd:dateTime;"                                       >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   dcterms:identifier   \"${usageDateTimeSlug}\";"                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   prov:specializationOf <${named_graph_global}>;"                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   prov:wasDerivedFrom ${latest_NG_nodeset:-"<$named_graph_global>"};"                             >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo ""                                                                                                  >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${named_graph_global}>"                                                                           >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   a sd:NamedGraph;"                                                                               >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   sd:name <$named_graph>;"                                                                        >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   dcterms:modified     \"${usageDateTime}\"^^xsd:dateTime;"                                       >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${PROV_BASE}sdService$requestID> a sd:Service;"                                                   >> ${TEMP}${unzipped}.load.pml.ttl
      if [ ${#CSV2RDF4LOD_PUBLISH_VIRTUOSO_SPARQL_ENDPOINT} -gt 0 ]; then
         echo "   sd:endpoint <$CSV2RDF4LOD_PUBLISH_VIRTUOSO_SPARQL_ENDPOINT>;"                                >> ${TEMP}${unzipped}.load.pml.ttl
      fi
      echo "   sd:availableGraphs <${PROV_BASE}collection$requestID>;"                                         >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${PROV_BASE}collection$requestID>"                                                                >> ${TEMP}${unzipped}.load.pml.ttl
      echo "  a sd:GraphCollection, dcat:Dataset;"                                                             >> ${TEMP}${unzipped}.load.pml.ttl
      echo "  sd:namedGraph <$named_graph_global>;"                                                            >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl
      echo                                                                                                     >> ${TEMP}${unzipped}.load.pml.ttl
      echo "<${PROV_BASE}activity${requestID}>"                                                                >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   a prov:Activity;"                                                                               >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   prov:used ${latest_NG_nodeset:-"<$named_graph_global>"}, <$url>;"                               >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   prov:wasAssociatedWith          `$CSV2RDF4LOD_HOME/bin/util/user-account.sh --cite`;"           >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   prov:qualifiedAssociation ["                                                                    >> ${TEMP}${unzipped}.load.pml.ttl
      echo "      a prov:Association;"                                                                         >> ${TEMP}${unzipped}.load.pml.ttl
      echo "      prov:agent `$CSV2RDF4LOD_HOME/bin/util/user-account.sh --cite`;"                             >> ${TEMP}${unzipped}.load.pml.ttl
      echo "      prov:hadPlan <http://inference-web.org/registry/MPR/RDFModelUnion.owl#RDFModelUnion>;"       >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   ];"                                                                                             >> ${TEMP}${unzipped}.load.pml.ttl
      echo "   prov:startedAtTime \"`$CSV2RDF4LOD_HOME/bin/util/dateInXSDDateTime.sh`\"^^xsd:dateTime;"        >> ${TEMP}${unzipped}.load.pml.ttl
      echo "."                                                                                                 >> ${TEMP}${unzipped}.load.pml.ttl


      #
      # Virtuoso can't handle all turtle files that rapper can.
      #

      vload=$CSV2RDF4LOD_HOME/bin/util/virtuoso/vload
      #echo $vload nt ${TEMP}${unzipped}.nt $named_graph
      if [ ${dryrun-"."} != "true" ]; then #        Actual response (in ntriples syntax).
         $vload nt ${TEMP}${unzipped}.nt              $named_graph 2>&1 | grep -v "Loading" 
         #cat /tmp/virtuoso-tmp/vload.log
      fi
      #echo $vload ttl ${TEMP}.pml.ttl      $named_graph
      if [ ${dryrun-"."} != "true" ]; then # Provenance of response (SourceUsage created by pcurl.sh).
         rapper -q -g -o ntriples ${TEMP}.pml.ttl > ${TEMP}.pml.ttl.nt
         $vload nt ${TEMP}.pml.ttl.nt                 $named_graph 2>&1 | grep -v "Loading"
         #cat /tmp/virtuoso-tmp/vload.log
      fi
      #echo $vload ttl ${TEMP}.load.pml.ttl  $named_graph
      if [ ${dryrun-"."} != "true" ]; then # Provenance of loading file into the store. TODO: cat ${TEMP}${unzipped}.load.pml.ttl into a pmlp:hasRawString?
         rapper -q -g -o ntriples ${TEMP}${unzipped}.load.pml.ttl > ${TEMP}${unzipped}.load.pml.ttl.nt
         $vload nt ${TEMP}${unzipped}.load.pml.ttl.nt $named_graph 2>&1 | grep -v "Loading"             
         #cat /tmp/virtuoso-tmp/vload.log
      fi
      echo "\\\\\\\\\\------------------------------ `basename $0` ------------------------------/////"
   else
      echo "WARNING: `basename $0` skipping b/c no triples returned."
   fi

   #
   # Clean up
   #
   if [ "$CSV2RDF4LOD_CONVERT_DEBUG_LEVEL" != "finest" ]; then
      rm -f ${TEMP}*
      rm -f ${TEMP}.unzipped
      rm -f ${TEMP}.unzipped.nt
      rm -f ${TEMP}.pml.ttl 
      rm -f ${TEMP}.pml.ttl.nt 
      rm -f ${TEMP}${unzipped} 
      rm -f ${TEMP}.nt
      rm -f ${TEMP}${unzipped}.nt
      rm -f ${TEMP}${unzipped}.load.pml.ttl 
      rm -f ${TEMP}${unzipped}.load.pml.ttl.nt
      rm -f _pvload*
   fi

   shift
done
