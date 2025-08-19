#get folder to process
#count total files initial
#create output folders
    #DELETE
    #VERTICAL
    #HORIZONTAL
    #PHOTOS
    #PHOTOS/RAW
    #PHOTOS/JPG
    #PHOTOS/Ephotos
#define file extensions
    #MP4
    #SRT, AAE, LRF - all together in DELETE
    #mov - check VERTICAL or HORIZONTAL
    #CR3, DNG - RAW
    #JPG, HEIC, JPEG, PNG - JPG

#Move IMG_E*** files to PHOTOS/Ephotos
#move SRT, AAE, LRF to DELETE
#move photos to /raw & /jpeg
#check file names in photos/raw against photos/jpg. 
#IF any missing in raw (IE HDR photos) COPY over to raw

#count total files again
#IF total_files_initial is not equal to total_files_after highlight delta as an error message



#for all video files only, get file names

############
#EDGE CASES#
############

#initial operations
#1 can't find any files in the folder
#2 can't find any valid files to process in the folder
#3 can't create folder (due to permissions)
#4 invalid file type (need to list every expected file type) - throws error of list of unexpected file types

#dimension checking
#5 height and width are numbers (not non-numeric chars)
#6 can't find dimensions
#7 dimensions are equal (video is square)



############
#FOR EACH MOVE OPERATION#
############
#count files to move
#move files
#count #of moved files
#if delta, throw error

############
#PROCESSING VIDEO FILES#
############


# Function to extract rotation from Display Matrix side data
get_rotation() {
    local file="$1"
    ffprobe -v error -select_streams v:0 \
        -show_entries side_data_list \
        -analyzeduration 0 \
        -read_intervals 0 \
        -probesize 32k \
        -of json "$file" | jq -r '
        .streams[0].side_data_list[]? 
        | select(.side_data_type == "Display Matrix") 
        | .rotation // empty
    '
    
    #-count_frames 0 \
}

#get folder to process
FOLDER_PATH="$1"

if [[ -z "$FOLDER_PATH" ]]; then
    read -rp "Enter the folder path: " FOLDER_PATH
fi

if [[ ! -d "$FOLDER_PATH" ]]; then
    echo "Error: '$FOLDER_PATH' is not a valid directory."
    exit 1
fi

#count total files initial
count=$(find "$FOLDER_PATH" -type f | wc -l)
echo "$count files total"



#create output folders
    #DELETE
    #VERTICAL
    #HORIZONTAL
    #PHOTOS
    #PHOTOS/RAW
    #PHOTOS/JPG
    #PHOTOS/Ephotos

# Folders to sort into
HORIZONTAL="$FOLDER_PATH/HORIZONTAL"
VERTICAL="$FOLDER_PATH/VERTICAL"
PHOTOS="$FOLDER_PATH/PHOTOS"
RAW="$FOLDER_PATH/PHOTOS/RAW"
JPG="$FOLDER_PATH/PHOTOS/JPG"
DELETE="$FOLDER_PATH/DELETE"
LIVE_PHOTOS="$FOLDER_PATH/Live Photos"
EPHOTOS="$FOLDER_PATH/E Photos"
VIDEOS="$FOLDER_PATH/VIDEOS"


# Create folders
mkdir -p "$VIDEOS" "$HORIZONTAL" "$VERTICAL" "$PHOTOS" "$RAW" "$JPG" "$DELETE" "$LIVE_PHOTOS" "$EPHOTOS"

#define file extensions
    #MP4
    #SRT, AAE, LRF - all together in DELETE
    #mov - check VERTICAL or HORIZONTAL
    #CR3, DNG - RAW
    #JPG, HEIC, JPEG, PNG - JPG

# File extensions
photo_exts="heic jpg jpeg png"
raw_exts="cr3 dng"
iphone_video_exts="mov"
other_video_exts="mp4"
metadata_exts="srt aae lrf"

#Move IMG_E*** files to PHOTOS/Ephotos
#move SRT, AAE, LRF to DELETE
#move photos to /raw & /jpeg

for FILE in "$FOLDER_PATH"/*; do
    [[ -f "$FILE" ]] || continue

    #basename strips the path, leaving just the filename.
    BASENAME=$(basename "$FILE")
    EXT="${FILE##*.}"
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

    # Move IMG_E*** files to E photos
    if [[ "$BASENAME" == IMG_E* ]]; then
        mv "$FILE" "$EPHOTOS/"
        echo "Moved $BASENAME to E photos/"
        continue
    fi

    # Move photo files
    if [[ " $photo_exts " =~ " $EXT_LOWER " ]]; then
        mv "$FILE" "$JPG/"
        echo "Moved $BASENAME to PHOTOS/JPG"
        continue
    fi

    # Move camera/drone files
    if [[ " $other_video_exts " =~ " $EXT_LOWER " ]]; then
        mv "$FILE" "$VIDEOS/"
        echo "Moved $BASENAME to VIDEOS"
        continue
    fi

    #move raw photo files
    if [[ " $raw_exts " =~ " $EXT_LOWER " ]]; then
        mv "$FILE" "$RAW/"
        echo "Moved $BASENAME to PHOTOS/RAW"    
        continue
    fi

    # Move metadata files
    if [[ " $metadata_exts " =~ " $EXT_LOWER " ]]; then
        mv "$FILE" "$DELETE/"
        echo "Moved $BASENAME to DELETE/"
        continue
    fi

    # Skip non-video files
    if [[ ! " $iphone_video_exts " =~ " $EXT_LOWER " ]]; then
        echo "Skipping $BASENAME: not a supported video file"
        continue
    fi


    #move iphone videos
    if [[ " $iphone_video_exts " =~ " $EXT_LOWER " ]]; then
        # Get raw dimensions
        RAW_DIMENSIONS=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=width,height \
            -of csv=s=x:p=0 "$FILE" 2>/dev/null)

        if [[ -z "$RAW_DIMENSIONS" ]]; then
            echo "Skipping $BASENAME: ffprobe returned no dimensions"
            continue
        fi

        # Remove trailing 'x' if present (needed for parsing)
        DIMENSIONS="${RAW_DIMENSIONS%x}"
        WIDTH=${DIMENSIONS%x*}
        HEIGHT=${DIMENSIONS#*x}

        if ! [[ "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]]; then
            echo "Skipping $BASENAME: invalid dimensions ($RAW_DIMENSIONS)"
            continue
        fi

        # Check for Live Photo resolution FIRST
        if [[ "$WIDTH" == "1440" || "$HEIGHT" == "1440" ]]; then
            mv "$FILE" "$LIVE_PHOTOS/"
            echo "Moved $BASENAME to Live Photos/"
            continue
        fi
        # ambiguous dimensions to be processed in 2nd pass
        if [[ "$RAW_DIMENSIONS" == *x ]]; then
            continue
        fi
        # Standard orientation detection
        if (( WIDTH > HEIGHT )); then
            mv "$FILE" "$HORIZONTAL/"
            echo "Moved $BASENAME to horizontal/"
        elif (( HEIGHT > WIDTH )); then
            mv "$FILE" "$VERTICAL/"
            echo "Moved $BASENAME to vertical/"
        else
            echo "$BASENAME is square, skipping."
        fi

        continue
    fi
done

#WAHT DOES THIS CODE DO??
for FILE in "$FOLDER_PATH"/*; do
    [[ -f "$FILE" ]] || continue
    # Get raw dimensions

    #TO DO - make this a constant (string that doesn't change) at the top of the file
    #this FFMPEG command extracts raw dimensions of file
    #TO DO - add all other FFMPEG commands as constants
    RAW_DIMENSIONS=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height \
        -of csv=s=x:p=0 "$FILE" 2>/dev/null)

    if [[ -z "$RAW_DIMENSIONS" ]]; then
        echo "Skipping $BASENAME: ffprobe returned no dimensions"
        continue
    fi

    # Remove trailing 'x' if present (needed for parsing)
    DIMENSIONS="${RAW_DIMENSIONS%x}"
    WIDTH=${DIMENSIONS%x*}
    HEIGHT=${DIMENSIONS#*x}

    #2nd pass processing
    TEMP="0"
    # Use Display Matrix rotation (if available)
    ROTATION=$(get_rotation "$FILE")
    echo "Rotation for $BASENAME: $ROTATION"
    echo "[PRE SWAP] Height = $HEIGHT | Width = $WIDTH"
    if [[ "$ROTATION" == "90" || "$ROTATION" == "-90" || "$ROTATION" == "270" || "$ROTATION" == "-270" ]]; then
        #mv "$FILE" "$VERTICAL/"
        #echo "Moved $BASENAME to vertical/ (rotation: $ROTATION)"
        TEMP=$HEIGHT
        HEIGHT=$WIDTH
        WIDTH=$TEMP
        echo "[Post Swap] Height = $HEIGHT | Width = $WIDTH"
    fi
    # Standard orientation detection - TO DO make this a function
    if (( WIDTH > HEIGHT )); then
        mv "$FILE" "$HORIZONTAL/"
        echo "Moved $BASENAME to horizontal/"
    elif (( HEIGHT > WIDTH )); then
        mv "$FILE" "$VERTICAL/"
        echo "Moved $BASENAME to vertical/"
    else
        echo "$BASENAME is square, skipping."
    fi

done   

#find and delete empty folders (Y to confirm)


#check file names in photos/raw against photos/jpg. 
#IF any missing in raw (IE HDR photos) COPY over to raw



#TO DO move this into a function - verify final media count
#count total files again
second_count=$(find "$FOLDER_PATH" -type f | wc -l)
echo "$count files found"
if (( second_count != count )); then
    echo "file counts do not match"
elif (( second_count == count )); then
    echo "file count matches initial count"
fi

#TO DO create report of what was changed, rather than printing everything in the terminal
#TO DO create error log

