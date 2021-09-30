#!/bin/bash

if [[ $(basename $(pwd)) != "elg" ]]; then
    echo "Run this script in the elg/ subdirectory."
fi

MODEL_VERSION="1.0.0"
LANGS=""
PAIRS=""
MODEL_COUNT=0

if [[ ! -d "models" ]]; then
    echo "models/ doesn't exist, creating it and fetching models listed in models.txt"
    mkdir models
    while read line; do
	# fetch and unpack each model
	wget $line
	mkdir -p models/$(basename $(dirname $line))
	unzip -o -d "models/$(basename $(dirname $line))" "$(basename $line)"
	rm "$(basename $line)"
    done < models.txt
else
    echo "Using existing directory models/"
fi

echo
for readme in $(find models/ -name "README.md"); do
    ((MODEL_COUNT+=1))
    # Parse README files, yaml would be nicer
    # xargs to trim whitespace :)
    THIS_SRC_LANGS=$(grep "source language" $readme | cut -d":" -f2 | xargs)
    THIS_TGT_LANGS=$(grep "target language" $readme | cut -d":" -f2 | xargs)
    echo "In $readme, found source languages ${THIS_SRC_LANGS} and target languages ${THIS_TGT_LANGS}"

    for src in $THIS_SRC_LANGS; do
	LANGS+="$src "
	for tgt in $THIS_TGT_LANGS; do
	    TEST_SIZE=$(grep 'Tatoeba-test' $readme | grep "${src}-${tgt}" | cut -f5 -d'|' | xargs)
	    if [[ $TEST_SIZE -ge 200 ]] || [[ "$TEST_SIZE" == "" ]]; then
		PAIRS+="$src-$tgt "
		LANGS+="$tgt "
	    fi
	done
    done
done

echo "Ended up with pairs: ${PAIRS}"
echo

IMAGE_NAME="opus-mt"
TAG_NAME=$(echo $LANGS | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs | tr ' ' '-')"-"$(date +%F)
if [[ "$#" -ge 1 ]]; then
    IMAGE_NAME=$1
fi
if [[ "$#" -ge 2 ]]; then
    TAG_NAME=$2
fi
if [[ "$#" -ge 3 ]]; then
    MODEL_VERSION=$3
fi


if ls *.xml 1> /dev/null 2>&1; then
    read -p "There are stale xml files present. Delete them? [y/n] " yn
    case $yn in
	[Yy]* ) rm -f *.xml;;
	* ) echo "OK, exiting so you can deal with them."; exit;;
    esac
fi
for pair in $PAIRS; do
    src_lang_opt="--source-lang $(echo $pair | cut -d"-" -f1)"
    tgt_lang_opt="--target-lang $(echo $pair | cut -d"-" -f2)"
    # src_region and tgt_region aren't used in Tatoeba, but generate_metadata knows about them
    python3 generate_metadata.py --version $MODEL_VERSION --image-name ${IMAGE_NAME}:${TAG_NAME} --models-in-image $MODEL_COUNT \
	    $src_lang_opt $tgt_lang_opt $src_region_opt $trg_region_opt
done
rm -f metadata_${IMAGE_NAME}_${TAG_NAME}.zip
zip metadata_${IMAGE_NAME}_${TAG_NAME}.zip *.xml
rm -f *.xml
echo "Wrote metadata in metadata_${IMAGE_NAME}_${TAG_NAME}.zip"

IMAGE_NAME="helsinkinlp/$IMAGE_NAME:$TAG_NAME"
echo "Building with name "$IMAGE_NAME

cd ..
sudo docker build . -f Dockerfile.base -t opus-mt-base

# This is an annoying hack needed to deal with the fact that elg/ is in the
# main .dockerignore, and some files needed by the Dockerfile for elg live
# in the main directory. We copy those files, use them, then delete them.

cp server.py content_processor.py write_configuration.py apply_bpe.py elg/
cd elg
python3 write_configuration.py > services.json
sudo docker build . -t $IMAGE_NAME
rm server.py content_processor.py write_configuration.py apply_bpe.py \
   services.json

read -p "Want to push image to Dockerhub now? [y/n] " yn
    case $yn in
	[Yy]* )
	    sudo docker login
	    sudo docker push $IMAGE_NAME;;
	* ) echo "Not pushing.";;
    esac

echo
echo "Done. Don't forget to upload metadata_$IMAGE_NAME_$MODEL_VERSION.zip to the ELG catalogue!"
