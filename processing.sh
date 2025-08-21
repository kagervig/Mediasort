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





#extract rotation from Display Matrix side data
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
    #return type is integer (typically a multiple of 90), may be negative
    #-count_frames 0 \
}

#uses an FFMPEG command to extract raw dimensions of file
#Takes a file path as an argument
#returns bash exit code of 0 or 1
#string in the format WIDTHxHEIGHT (e.g. 1920x1080)
get_raw_dimensions() {
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

#takes width and height as arguments
#determines which folder to move the file to based on orientation
move_file_by_orientation(){
    local width="$1"
    local height="$2"
    if (( width > height )); then
        mv "$FILE" "$HORIZONTAL/"
    elif (( height > width )); then
        mv "$FILE" "$VERTICAL/"
    fi
}

#find and delete empty folders (Y to confirm)
delete_empty_folders() {
    local FOLDER_PATH="$1"
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
            fi
        fi
    done
}

#check file names in photos/raw against photos/jpg. 
#IF any missing in raw (IE HDR photos) COPY over to raw
#declare empty array to hold raw file names
copy_non_raw_photos (){
    local RAW_PHOTOS="$1"
    raw_files_list=()
    for files in "$RAW_PHOTOS"/*; do
        #build list of raw file names (not extensions)
        BASENAME=$(basename "$files")
        raw_files_list+=("${BASENAME%.*}")
    done

   for file in "$PHOTOS"/*; do
        #extract jpg filename without extension
        BASENAME=$(basename "$file")
        #check if file is a jpg
        image_ext="${file##*.}"
        echo "$BASENAME has extension $image_ext"

        #ignores any non JPG files
        if [[ "$image_ext" == "JPG" ]]; then
            jpg_no_extension="${BASENAME%.*}"
            echo "Checking if $jpg_no_extension is in raw files array"
            #check if the file name is in the raw_files array
            if [[ ! " ${raw_files_list[@]} " =~ " $jpg_no_extension " ]]; then
                cp "$file" "$RAW_PHOTOS/"
                echo "Copied $jpg_no_extension to $RAW_PHOTOS/"
            fi
        fi
    done
    echo "Copied all non-raw photos!"
}

#count total files again (check nothing was deleted)
validate_file_count() {
    local FOLDER_PATH="$1"
    second_count=$(find "$FOLDER_PATH" -type f | wc -l)
    echo "$count files found"  >&2 
    if (( second_count != count )); then
        echo "file counts do not match"  >&2 
    elif (( second_count == count )); then
        echo "file count matches initial count"  >&2 
    fi
}

#Move IMG_E*** files to PHOTOS/Ephotos
#move SRT, AAE, LRF files to DELETE
#separate raw and jpg photos respectively
sort_media_files() {
    local FOLDER_PATH="$1"
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

        # Move photo files (jpg, heic, png)
        if [[ " $PHOTO_EXTS " =~ " $EXT_LOWER " ]]; then
            mv "$FILE" "$PHOTOS/"
            echo "Moved $BASENAME to PHOTOS"
            continue
        fi

        # Move camera/drone files
        if [[ " $OTHER_VIDEO_EXTS " =~ " $EXT_LOWER " ]]; then
            mv "$FILE" "$VIDEOS/"
            echo "Moved $BASENAME to VIDEOS"
            continue
        fi

        #move raw photo files (dng, cr3)
        if [[ " $RAW_EXTS " =~ " $EXT_LOWER " ]]; then
            mv "$FILE" "$RAW_PHOTOS/"
            echo "Moved $BASENAME to RAW PHOTOS"    
            continue
        fi

        # Move metadata files
        if [[ " $METADATA_EXTS " =~ " $EXT_LOWER " ]]; then
            mv "$FILE" "$DELETE/"
            echo "Moved $BASENAME to DELETE/"
            continue
        fi

        # Skip non-video files
        if [[ ! " $IPHONE_VIDEO_EXTS " =~ " $EXT_LOWER " ]]; then
            echo "Skipping $BASENAME: not a supported video file"
            continue
        fi


        #move iphone videos
        if [[ " $IPHONE_VIDEO_EXTS " =~ " $EXT_LOWER " ]]; then
            #gets raw dimensions of file
            RAW_DIMENSIONS=$(get_raw_dimensions "$FILE")
            status=$?
            #if function fails, or returns empty, skip the file
            if [[ $status -ne 0 || -z "$RAW_DIMENSIONS" ]]; then
                echo "Skipping $BASENAME (status=$status, dims='$RAW_DIMENSIONS')"
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

            # check if live photo based on dimensions
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
            move_file_by_orientation "$WIDTH" "$HEIGHT"

            continue
        fi
    done
}

#By this point, only files with "x" at the end of the dimensions remain
#this usses FFMPEG to get rotation flag
#if rotation flag is set, dimensions are swapped
#it is kept separate and performed last as it is slower than every other operation
swap_video_dimensions() {
    for FILE in "$FOLDER_PATH"/*; do
        [[ -f "$FILE" ]] || continue

    #gets raw dimensions of file
        RAW_DIMENSIONS=$(get_raw_dimensions "$FILE")
        status=$?
        #if function fails, or returns empty, skip the file
        if [[ $status -ne 0 || -z "$RAW_DIMENSIONS" ]]; then
            echo "Skipping $BASENAME (status=$status, dims='$RAW_DIMENSIONS')"
            continue
        fi

        # Remove trailing 'x' if present (needed for parsing)
        DIMENSIONS="${RAW_DIMENSIONS%x}"
        WIDTH=${DIMENSIONS%x*}
        HEIGHT=${DIMENSIONS#*x}

        TEMP="0"
        # Use Display Matrix rotation (if available)
        echo "Getting rotation for $FILE"
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
        move_file_by_orientation "$WIDTH" "$HEIGHT"

    done   
}


#################
#EXECUTION BEGINS
#################

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
#TEST="$FOLDER_PATH/TEST"

#define file extensions
    #MP4
    #SRT, AAE, LRF - all together in DELETE
    #mov - check VERTICAL or HORIZONTAL
    #CR3, DNG - RAW
    #JPG, HEIC, JPEG, PNG - JPG

# File extensions
PHOTO_EXTS="heic jpg jpeg png"
RAW_EXTS="cr3 dng"
IPHONE_VIDEO_EXTS="mov"
OTHER_VIDEO_EXTS="mp4"
METADATA_EXTS="srt aae lrf"

# Create folders
mkdir -p "$VIDEOS" "$HORIZONTAL" "$VERTICAL" "$PHOTOS" "$RAW_PHOTOS" "$DELETE" "$LIVE_PHOTOS" "$EPHOTOS"
#mkdir -p "$TEST" #for testing purposes

sort_media_files "$FOLDER_PATH" #1st pass - sorting files by type and dimensions

echo " " #adds newline in terminal for readability

swap_video_dimensions "$FOLDER_PATH" #2nd pass for files with ambiguous dimensions

delete_empty_folders "$FOLDER_PATH" #cleanup

file_count_output=$(validate_file_count "$FOLDER_PATH") #validation of file count
echo "$file_count_output"

non_raw_photos_status=$(copy_non_raw_photos "$RAW_PHOTOS") #copy non-raw photos for convenience
echo "$non_raw_photos_status"





#TO DO mute drone and camera videos

#TO DO create report of what was changed, rather than printing everything in the terminal
#TO DO create error log

