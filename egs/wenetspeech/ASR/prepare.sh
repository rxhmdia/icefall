#!/usr/bin/env bash

set -eou pipefail

nj=15
stage=0
stop_stage=100

# Split L subset to this number of pieces
# This is to avoid OOM during feature extraction.
num_splits=1000

# We assume dl_dir (download dir) contains the following
# directories and files. If not, they will be downloaded
# by this script automatically.
#
#  - $dl_dir/WenetSpeech
#      You can find audio, WenetSpeech.json inside it.
#      You can apply for the download credentials by following
#      https://github.com/wenet-e2e/WenetSpeech#download
#
#  - $dl_dir/musan
#      This directory contains the following directories downloaded from
#       http://www.openslr.org/17/
#
#     - music
#     - noise
#     - speech

dl_dir=$PWD/download

. shared/parse_options.sh || exit 1

# All files generated by this script are saved in "data".
# You can safely remove "data" and rerun this script to regenerate it.
mkdir -p data

log() {
  # This function is from espnet
  local fname=${BASH_SOURCE[1]##*/}
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}

log "dl_dir: $dl_dir"

if [ $stage -le 0 ] && [ $stop_stage -ge 0 ]; then
  log "Stage 0: Download data"

  [ ! -e $dl_dir/WenetSpeech ] && mkdir -p $dl_dir/WenetSpeech

  # If you have pre-downloaded it to /path/to/WenetSpeech,
  # you can create a symlink
  #
  # ln -sfv /path/to/WenetSpeech $dl_dir/WenetSpeech
  #
  if [ ! -d $dl_dir/WenetSpeech/wenet_speech ] && [ ! -f $dl_dir/WenetSpeech/metadata/v1.list ]; then
    log "Stage 0: should download WenetSpeech first"
    exit 1;
  fi

  # If you have pre-downloaded it to /path/to/musan,
  # you can create a symlink
  #
  #ln -sfv /path/to/musan $dl_dir/musan

  if [ ! -d $dl_dir/musan ]; then
    lhotse download musan $dl_dir
  fi
fi

if [ $stage -le 1 ] && [ $stop_stage -ge 1 ]; then
  log "Stage 1: Prepare WenetSpeech manifest"
  # We assume that you have downloaded the WenetSpeech corpus
  # to $dl_dir/WenetSpeech
  mkdir -p data/manifests
  lhotse prepare wenet-speech $dl_dir/WenetSpeech data/manifests -j $nj
fi

if [ $stage -le 2 ] && [ $stop_stage -ge 2 ]; then
  log "Stage 2: Prepare musan manifest"
  # We assume that you have downloaded the musan corpus
  # to data/musan
  mkdir -p data/manifests
  lhotse prepare musan $dl_dir/musan data/manifests
fi

if [ $stage -le 3 ] && [ $stop_stage -ge 3 ]; then
  log "Stage 3: Preprocess WenetSpeech manifest"
  if [ ! -f data/fbank/.preprocess_complete ]; then
    python3 ./local/preprocess_wenetspeech.py
    touch data/fbank/.preprocess_complete
  fi
fi

if [ $stage -le 4 ] && [ $stop_stage -ge 4 ]; then
  log "Stage 4: Compute features for DEV and TEST subsets of WenetSpeech (may take 2 minutes)"
  python3 ./local/compute_fbank_wenetspeech_dev_test.py
fi

if [ $stage -le 5 ] && [ $stop_stage -ge 5 ]; then
  log "Stage 5: Split S subset into ${num_splits} pieces"
  split_dir=data/fbank/S_split_${num_splits}_test
  if [ ! -f $split_dir/.split_completed ]; then
    lhotse split $num_splits ./data/fbank/cuts_S_raw.jsonl.gz $split_dir
    touch $split_dir/.split_completed
  fi
fi

if [ $stage -le 6 ] && [ $stop_stage -ge 6 ]; then
  log "Stage 6: Split M subset into ${num_splits} piece"
  split_dir=data/fbank/M_split_${num_splits}
  if [ ! -f $split_dir/.split_completed ]; then
    lhotse split $num_splits ./data/fbank/cuts_M_raw.jsonl.gz $split_dir
    touch $split_dir/.split_completed
  fi
fi

if [ $stage -le 7 ] && [ $stop_stage -ge 7 ]; then
  log "Stage 7: Split L subset into ${num_splits} pieces"
  split_dir=data/fbank/L_split_${num_splits}
  if [ ! -f $split_dir/.split_completed ]; then
    lhotse split $num_splits ./data/fbank/cuts_L_raw.jsonl.gz $split_dir
    touch $split_dir/.split_completed
  fi
fi

if [ $stage -le 8 ] && [ $stop_stage -ge 8 ]; then
  log "Stage 8: Compute features for S"
  python3 ./local/compute_fbank_wenetspeech_splits.py \
    --training-subset S \
    --num-workers 20 \
    --batch-duration 600 \
    --start 0 \
    --num-splits $num_splits
fi

if [ $stage -le 9 ] && [ $stop_stage -ge 9 ]; then
  log "Stage 9: Compute features for M"
  python3 ./local/compute_fbank_wenetspeech_splits.py \
    --training-subset M \
    --num-workers 20 \
    --batch-duration 600 \
    --start 0 \
    --num-splits $num_splits
fi

if [ $stage -le 10 ] && [ $stop_stage -ge 10 ]; then
  log "Stage 10: Compute features for L"
  python3 ./local/compute_fbank_wenetspeech_splits.py \
    --training-subset L \
    --num-workers 20 \
    --batch-duration 600 \
    --start 0 \
    --num-splits $num_splits
fi

if [ $stage -le 11 ] && [ $stop_stage -ge 11 ]; then
  log "Stage 11: Combine features for S"
  if [ ! -f data/fbank/cuts_S.jsonl.gz ]; then
    pieces=$(find data/fbank/S_split_1000 -name "cuts_S.*.jsonl.gz")
    lhotse combine $pieces data/fbank/cuts_S.jsonl.gz
  fi
fi

if [ $stage -le 12 ] && [ $stop_stage -ge 12 ]; then
  log "Stage 12: Combine features for M"
  if [ ! -f data/fbank/cuts_M.jsonl.gz ]; then
    pieces=$(find data/fbank/M_split_1000 -name "cuts_M.*.jsonl.gz")
    lhotse combine $pieces data/fbank/cuts_M.jsonl.gz
  fi
fi

if [ $stage -le 13 ] && [ $stop_stage -ge 13 ]; then
  log "Stage 13: Combine features for L"
  if [ ! -f data/fbank/cuts_L.jsonl.gz ]; then
    pieces=$(find data/fbank/L_split_1000 -name "cuts_L.*.jsonl.gz")
    lhotse combine $pieces data/fbank/cuts_L.jsonl.gz
  fi
fi

if [ $stage -le 14 ] && [ $stop_stage -ge 14 ]; then
  log "Stage 14: Compute fbank for musan"
  mkdir -p data/fbank
  ./local/compute_fbank_musan.py
fi

if [ $stage -le 15 ] && [ $stop_stage -ge 15 ]; then
  log "Stage 15: Prepare char based lang"
  lang_char_dir=data/lang_char
  mkdir -p $lang_char_dir

  # Prepare text.
  # Note: in Linux, you can install jq with the following command:
  # wget -O jq https://github.com/stedolan/jq/release/download/jq-1.6/jq-linux64
  if [ ! -f $lang_char_dir/text ]; then
    gunzip -c data/manifests/supervisions_L.jsonl.gz \
      | jq 'text' | sed 's/"//g' \
      | ./local/text2token.py -t "char" > $lang_char_dir/text
  fi

  # The implementation of chinese word segmentation for text,
  # and it will take about 15 minutes.
  if [ ! -f $lang_char_dir/text_words_segmentation ]; then
    python ./local/text2segments.py \
      --input-file $lang_char_dir/text \
      --output-file $lang_char_dir/text_words_segmentation
  fi

  cat $lang_char_dir/text_words_segmentation | sed 's/ /\n/g' \
    | sort -u | sed '/^$/d' | uniq > $lang_char_dir/words_no_ids.txt

  if [ ! -f $lang_char_dir/words.txt ]; then
    python ./local/prepare_words.py \
      --input-file $lang_char_dir/words_no_ids.txt \
      --output-file $lang_char_dir/words.txt
  fi
fi

if [ $stage -le 16 ] && [ $stop_stage -ge 16 ]; then
  log "Stage 16: Prepare char based L_disambig.pt"
  if [ ! -f data/lang_char/L_disambig.pt ]; then
    python ./local/prepare_char.py \
      --lang-dir data/lang_char
  fi
fi
