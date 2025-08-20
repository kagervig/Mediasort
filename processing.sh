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

#this function uses an FFMPEG command to extract raw dimensions of file
GET_RAW_DIMENSIONS() {
    local file="$1"
    local dims
    dims=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height \
        -of csv=s=x:p=0 "$file" 2>/dev/null)

    if [[ -z "$dims" ]]; then
        echo "Error: ffprobe returned no dimensions for $file" >&2
        return 1
    fi

    echo "$dims"
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
RAW_PHOTOS="$FOLDER_PATH/RAW PHOTOS"
PHOTOS="$FOLDER_PATH/PHOTOS"
DELETE="$FOLDER_PATH/DELETE"
LIVE_PHOTOS="$FOLDER_PATH/Live Photos"
EPHOTOS="$FOLDER_PATH/E Photos"
VIDEOS="$FOLDER_PATH/VIDEOS"


# Create folders
mkdir -p "$VIDEOS" "$HORIZONTAL" "$VERTICAL" "$PHOTOS" "$RAW_PHOTOS" "$DELETE" "$LIVE_PHOTOS" "$EPHOTOS"

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

    #basename gives the file name + extension
    BASENAME=$(basename "$FILE")
    #extracts the extension from the file name
    EXT="${FILE##*.}"
    #makes the extension lowercase
    EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

    # Move IMG_E*** files to E photos
    if [[ "$BASENAME" == IMG_E* ]]; then
        mv "$FILE" "$EPHOTOS/"
        echo "Moved $BASENAME to E photos/"
        continue
    fi

    # Move photo files
    if [[ " $photo_exts " =~ " $EXT_LOWER " ]]; then
        mv "$FILE" "$PHOTOS/"
        echo "Moved $BASENAME to PHOTOS"
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
        mv "$FILE" "$RAW_PHOTOS/"
        echo "Moved $BASENAME to RAW PHOTOS"    
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
        if ! RAW_DIMENSIONS=$(GET_RAW_DIMENSIONS "$FILE"); then
            echo "Skipping $BASENAME"
            continue
        fi


        # Removes trailing 'x' if present (needed for parsing)
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

#This uses ffprobe to check real dimensions and rotation flag of a video
#in order to determine whether it is horizontal or vertical
#it is kept separate and performed last as it is slower than every other operation
for FILE in "$FOLDER_PATH"/*; do
    [[ -f "$FILE" ]] || continue

    # Gets raw dimensions using ffmpeg command
    if ! RAW_DIMENSIONS=$(GET_RAW_DIMENSIONS "$FILE"); then
        echo "Skipping $BASENAME"
        continue
    fi

    # Remove trailing 'x' if present (needed for parsing)
    DIMENSIONS="${RAW_DIMENSIONS%x}"
    WIDTH=${DIMENSIONS%x*}
    HEIGHT=${DIMENSIONS#*x}

    TEMP="0"
    # Use Display Matrix rotation (if available)
    ROTATION=$(get_rotation "$FILE")
    echo "Rotation for $BASENAME: $ROTATION"
    echo "[PRE SWAP] Height = $HEIGHT | Width = $WIDTH"
    if [[ "$ROTATION" == "90" || "$ROTATION" == "-90" || "$ROTATION" == "270" || "$ROTATION" == "-270" ]]; then
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
for dir in "$FOLDER_PATH"/*/; do
    #check if it is a directory
    [[ -d "$dir" ]] || continue
    #count files inside the directory
    file_count=$(find "$dir" -type f | wc -l)
    #if no files, ask to delete the directory
    if (( file_count == 0 )); then
        echo "no files found in $dir, do you want to delete it? (Y/n)"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "Deleting empty directory: $dir"
            rm -rf "$dir"
        elif [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo "Skipping deletion of $dir"
        else
            echo "Invalid input, skipping deletion of $dir"
        fi
    else
        echo "Directory $dir is not empty, skipping."
    fi
done

#check file names in photos/raw against photos/jpg. 
#IF any missing in raw (IE HDR photos) COPY over to raw
echo "Checking for missing RAW files in $RAW_PHOTOS against JPG files in $PHOTOS"
#declare empty array to hold raw file names
raw_files=()
for files in "$RAW_PHOTOS"/*; do
    #build list of raw file names (not extensions)
    BASENAME=$(basename "$files")
    raw_files+=("${BASENAME%.*}")
    echo "Raw file: $BASENAME"
done


#i have a list of raw file names, now I need to check against jpg files
#to do this i need to loop through jpg files and check if the name is in the raw_files array
#i'll need to get the basename of each jpg file and check if it is in the raw_files array
for file in "$PHOTOS"/*; do
    #extract jpg filename without extension
    BASENAME=$(basename "$file")
    #check if file is a jpg
    image_ext="${file##*.}"
    echo "$BASENAME has extension $image_ext"

    if [[ "$image_ext" == "JPG" ]]; then
        jpg_no_extension="${BASENAME%.*}"
        echo "Checking if $jpg_no_extension is in raw files array"
        #check if the file name is in the raw_files array
        if [[ ! " ${raw_files[@]} " =~ " $jpg_no_extension " ]]; then
            cp "$file" "$RAW_PHOTOS/"
            echo "Copied $file to $RAW_PHOTOS/"
        fi
    fi
done

#TO DO mute drone and camera videos

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

