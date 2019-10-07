#/usr/bin/fish

function build_app -d "Build apps for Graham Digital"
    set ex_t 0
    set bversion
    set upload 1
    set taggit 0

    if test -e ./gradle
        set app_type "android"
    else if test 0 -lt (find . -maxdepth 1 -name "*.xcworkspace" | wc -l)
        set app_type "apple"
    else
        printf "Couldn't find gradle or xcodeproject, unknown build\n"
        return 3
    end

    if test -d Flavors
        set FLAVORS (ls Flavors/)
    else
        printf "Cannot find Flavors directory\n"
    end

    set build_dir (realpath build_script)
    mkdir -p $build_dir

    if test -d $build_dir
        set BUILD_LOG $build_dir/build_log.log
        date >$BUILD_LOG
    else
        printf "Unable to create build directory\n"
        return 2
    end

    getopts $argv | while read -l key value
        switch $key
            case f flavors
                set FLAVORS (string split "," $value)
            case u upload
                set upload 0
            case v bversion
                set bversion $value
            case g "tag-git"
                set taggit 1
            case _
                printf "error: Unknown option %s\n" $option
        end
    end

    set OLD_VERSION_NAME (grep VERSION_NAME version.properties | cut -d'=' -f2)

    if test -z $bversion
        printf "Previous public version of the app: %s\n\n" $OLD_VERSION_NAME
        printf "Enter new version number \n"
        read bversion
        printf "User input: %s" $bversion >>$BUILD_LOG
    end

    printf (set_color cyan --bold)"Building apps: %s\nVersion: %s\n"(set_color normal) (string join ", " $FLAVORS) (echo $bversion; or "??")
    set OLD_VERSION_CODE (grep VERSION_CODE version.properties | cut -d'=' -f2)
    set NEW_VERSION_CODE (math $OLD_VERSION_CODE+1)
    echo "VERSION_CODE=$NEW_VERSION_CODE" >version.properties
    echo "VERSION_NAME=$bversion" >>version.properties

    if test "$app_type" = "apple"
        if test $upload -ne 0
            if test -z $ITC_PW
                printf "Upload is set, but no iTunesConnect password specified, unset upload with -u or set \$ITC_PW"
                return 3
            else if test -z $ITC_USER
                printf "Upload is set, but no iTunesConnect user specified, unset upload with -u or set \$ITC_USER"
                return 3
            end
        end

        printf (set_color blue)"\nUpdating Pods.\n"(set_color normal)
        pod update 2>&1 >>$BUILD_LOG

        if test $status -ne 0
            printf (set_color --reverse --bold red)"Failed to update CocoaPods, aborting.\a"(set_color normal)
            exit 2
        end

        for flavor in $FLAVORS
            if test ! -e Flavors/$flavor/$flavor-info.plist
                printf "Ignoring %s, missing plist to build. Perhaps it is an enterprise?\n" $flavor
                continue
            end

            set -l scheme_exists 0
            for scheme in (xcodebuild -workspace *.xcworkspace -allowProvisioningUpdates -list)
                if test (string trim $scheme) = $flavor
                    set scheme_exists 1
                    break
                end
            end

            if test $scheme_exists -eq 0
                printf "Ignoring %s: Scheme not found in project.\n" $flavor
                continue
            end

            printf "\n"

            python3 (dirname (status -f))/__versions.py release -v $bversion Flavors/$flavor/$flavor-info.plist
            python3 (dirname (status -f))/__versions.py build -v $NEW_VERSION_CODE Flavors/$flavor/$flavor-info.plist

            for variant in (find Flavors/$flavor -name Info.plist)
                python3 (dirname (status -f))/__versions.py release -v $bversion $variant >/dev/null
                python3 (dirname (status -f))/__versions.py build -v $NEW_VERSION_CODE $variant >/dev/null
            end

            printf (set_color yellow)"\n%s: Building version %s (%s).\n"(set_color normal) $flavor $bversion $NEW_VERSION_CODE
            printf "%s - %s\n" $bversion Flavors/$flavor/$flavor-info.plist

            xcodebuild -workspace *.xcworkspace -allowProvisioningUpdates -scheme $flavor clean archive -archivePath build/$flavor.xcarchive DEVELOPMENT_TEAM=AEJ335Y6NL 2>&1 >>$BUILD_LOG
            if test $status -ne 0
                printf (set_color red)"%s: Failed to build.\n"(set_color normal) $flavor
                set ex_t 2
                continue
            end

            xcodebuild -exportArchive -allowProvisioningUpdates -archivePath build/$flavor.xcarchive -exportPath build -exportOptionsPlist export.plist 2>&1 >>$BUILD_LOG

            if test $status -ne 0
                printf (set_color red)"%s: Failed to sign.\n"(set_color normal) $flavor
                set ex_t 2
                continue
            end

            if test $upload -ne 0
                printf (set_color yellow)"%s: Uploading to Apple.\n"(set_color normal) $flavor
                xcrun altool --upload-app -f build/$flavor.ipa -u $ITC_USER -p $ITC_PW 2>&1 >>$BUILD_LOG

                if test $status -ne 0
                    printf (set_color red)"%s: Failed to upload.\n"(set_color normal) $flavor
                    set ex_t 2
                else
                    printf (set_color green)"%s: Successfully uploaded.\n"(set_color normal) $flavor
                end
            end
        end
    else if test "$app_type" = "android"
        printf "Cleaning project\n\n"

        ./gradlew clean 2>&1 >>$BUILD_LOG

        if test $status -ne 0
            printf "Failed to clean, aborting"
            return 2
        end

        for flavor in $FLAVORS
            if test $flavor != "demo"
                and test $upload -ne 0
                printf "%s: building version %s (%s)\n\n" $flavor $bversion $NEW_VERSION_CODE
                ./gradlew publish{$flavor}ReleaseBundle 2>&1 >>$BUILD_LOG

                if test $status -ne 0
                    printf (set_color red)"%s: Failed to build and upload\n\n"(set_color normal) $flavor
                    set ex_t 2
                else
                    printf (set_color green)"%s: Built and Uploaded\n\n"(set_color normal) $flavor
                end
            else
                ./gradlew assemble{$flavor} 2>&1 >>$BUILD_LOG

                if test $status -ne 0
                    printf (set_color red)"%s: Failed to build and upload\n\n"(set_color normal) $flavor
                    set ex_t 2
                else
                    printf "%s: Built\n\n" $flavor
                end
            end
        end
    end

    if test $ex_t -ne 0
        printf (set_color --reverse --bold red)"Not all builds were successful\n\a"(set_color normal)
        return $ex_t
    else if test $taggit -ne 0
        git add "version.properties"
        git commit -m "Auto build $bversion($NEW_VERSION_CODE)"
        and \
            git tag "nightly/$NEW_VERSION_CODE"
        and \
            git push
        and \
            git push --tags
    end
end
