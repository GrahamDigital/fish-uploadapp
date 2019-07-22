#/usr/bin/fish

function build_app -d "Build apps for Graham Digital"
    set FLAVORS (ls Flavors/)
    set ex_t 0
    set bversion
    set upload 1
    set -l app_type "unknown"

    mkdir -p build
    set BUILD_LOG build/build_log.log

    date >$BUILD_LOG

    getopts $argv | while read -l key value
        switch $key
            case f flavors
                set FLAVORS (string split "," $value)
            case u upload
                set upload 0
            case v bversion
                set bversion $value
            case _
                printf "error: Unknown option %s\n" $option
        end
    end

    if test -e ./gradle
        set app_type "android"
    else if test -n '(find . -name "*.xcodeproj")'
        set app_type "apple"
    else
        printf "Couldn't find gradle or xcodeproject, unknown build"
        exit 3
    end

    set flavor (random choice $FLAVORS)

    set OLD_VERSION_NAME (grep VERSION_NAME version.properties | cut -d'=' -f2)

    if test -z $bversion
        printf "Previous public version of the app: %s\n\n" $OLD_VERSION_NAME
        printf "Enter new version number \n"
        read bversion
        printf "User input: %s" $bversion >>$BUILD_LOG
    end

    printf "Building apps: %s\nVersion: %s\n" (string join ", " $FLAVORS) (echo $bversion; or "??")
    set OLD_VERSION_CODE (grep VERSION_CODE version.properties | cut -d'=' -f2)
    set NEW_VERSION_CODE (math $OLD_VERSION_CODE+1)
    echo "VERSION_CODE=$NEW_VERSION_CODE" > version.properties
    echo "VERSION_NAME=$bversion" >> version.properties

    function build_apple
        if test $upload -ne 0
            if test -z $ITC_PW
                printf "Upload is set, but no ITunesConnect password specified, unset upload with -u or set \$ITC_PW"
                exit 3
            else if test -z $ITC_USER
                printf "Upload is set, but no ITunesConnect user specified, unset upload with -u or set \$ITC_USER"
                exit 3
            end
        end

        printf "Updating Pods\n"
        pod update 2>&1 >>$BUILD_LOG

        if test $status -ne 0
            printf "Failed to update CocoaPods, aborting"
            exit 2
        end

        for flavor in $FLAVORS
            if test ! -e Flavors/$flavor/$flavor-info.plist
                printf "Ignoring %s, missing plist to build. Perhaps it is an enterprise?\n\n" $flavor
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
                printf "Ignoring %s: Scheme not found in project\n" $flavor
                continue
            end
            printf "%s - %s" $bversion Flavors/$flavor/$flavor-info.plist
            python3 (dirname (status -f))/__versions.py release -v $bversion Flavors/$flavor/$flavor-info.plist
            python3 (dirname (status -f))/__versions.py build -v $NEW_VERSION_CODE Flavors/$flavor/$flavor-info.plist

            for variant in (find Flavors/$flavor -name Info.plist)
                python3 (dirname (status -f))/__versions.py release -v $bversion $variant >/dev/null
                python3 (dirname (status -f))/__versions.py build -v $NEW_VERSION_CODE $variant >/dev/null
            end

            printf "%s: building version %s (%s)\n" $flavor $bversion $NEW_VERSION_CODE

            xcodebuild -workspace *.xcworkspace -allowProvisioningUpdates -scheme $flavor clean archive -archivePath build/$flavor.xcarchive DEVELOPMENT_TEAM=AEJ335Y6NL 2>&1 >>$BUILD_LOG
            if test $status -ne 0
                printf "%s: Failed to build" $flavor
                set ex_t 2
                continue
            end

            xcodebuild -exportArchive -allowProvisioningUpdates -archivePath build/$flavor.xcarchive -exportPath build -exportOptionsPlist export.plist 2>&1 >>$BUILD_LOG

            if test $status -ne 0
                printf "%s: Failed to sign\n" $flavor
                set ex_t 2
                continue
            end

            if test $upload -ne 0
                printf "Uploading App %s\n" $flavor
                /Applications/Xcode.app/Contents/Applications/Application\ Loader.app/Contents/Frameworks/ITunesSoftwareService.framework/Versions/A/Support/altool --upload-app -f build/$flavor.ipa -u $ITC_USER -p $ITC_PW 2>&1 >>$BUILD_LOG

                if test $status -ne 0
                    printf "%s: Failed to upload\n" $flavor
                    set ex_t 2
                else
                    printf "%s: Successfully uploaded\n" $flavor
                end
            end
        end
    end

    function build_android
        printf "Cleaning project\n\n"

        ./gradlew clean 2>&1 >>$BUILD_LOG

        if test $status -ne 0
            printf "Failed to clean, aborting"
            exit 2
        end

        for flavor in $FLAVORS
            if test $flavor != "demo"; and test $upload -ne 0
                printf "%s: building version %s (%s)\n\n" $flavor $bversion $NEW_VERSION_CODE
                ./gradlew publish{$flavor}ReleaseBundle 2>&1 >>$BUILD_LOG

                if test $status -ne 0
                    printf "%s: Failed to build and upload\n\n" $flavor
                    set ex_t 2
                else
                    printf "%s: Built and Uploaded\n\n" $flavor
                end
            else
                ./gradlew assemble{$flavor} 2>&1 >>$BUILD_LOG

                if test $status -ne 0
                    printf "%s: Failed to build and upload\n\n" $flavor
                    set ex_t 2
                else
                    printf "%s: Built\n\n" $flavor
                end
            end
        end
    end

    if test "$app_type" = "apple"
        build_apple
    else if test "$app_type" = "android"
        build_android
    end

    if test $ex_t -ne 0
        printf "Not all builds were successful\n"
        exit $ex_t
    end
end
