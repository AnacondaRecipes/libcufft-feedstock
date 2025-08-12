#!/bin/bash

# Install to conda style directories
[[ -d lib64 ]] && mv lib64 lib
mkdir -p ${PREFIX}/lib
[[ -d pkg-config ]] && mv pkg-config ${PREFIX}/lib/pkgconfig
[[ -d "$PREFIX/lib/pkgconfig" ]] && sed -E -i "s|cudaroot=.+|cudaroot=$PREFIX|g" $PREFIX/lib/pkgconfig/cufft*.pc

[[ ${target_platform} == "linux-64" ]] && targetsDir="targets/x86_64-linux"
[[ ${target_platform} == "linux-ppc64le" ]] && targetsDir="targets/ppc64le-linux"
[[ ${target_platform} == "linux-aarch64" ]] && targetsDir="targets/sbsa-linux"

for i in *; do
    [[ $i == "build_env_setup.sh" ]] && continue
    [[ $i == "conda_build.sh" ]] && continue
    [[ $i == "metadata_conda_debug.yaml" ]] && continue
    if [[ $i == "lib" ]] || [[ $i == "include" ]]; then
        # Headers and libraries are installed to targetsDir
        mkdir -p ${PREFIX}/${targetsDir}
        mkdir -p ${PREFIX}/$i
        cp -rv $i ${PREFIX}/${targetsDir}
        if [[ $i == "lib" ]]; then
            for j in "$i"/*.so*; do
                # Shared libraries are symlinked in $PREFIX/lib
                ln -s ${PREFIX}/${targetsDir}/$j ${PREFIX}/$j
            done
        fi
    else
        # Put all other files in targetsDir
        mkdir -p ${PREFIX}/${targetsDir}/${PKG_NAME}
        cp -rv $i ${PREFIX}/${targetsDir}/${PKG_NAME}
    fi
done

# Fix RPATH for all real library files (not symlinks, not stubs)
echo "Looking for libraries in: ${PREFIX}/${targetsDir}/lib/"
ls -la ${PREFIX}/${targetsDir}/lib/ || true
for lib in ${PREFIX}/${targetsDir}/lib/*.so*; do
    # Skip symlinks and stub libraries
    if [[ -L "$lib" ]] || [[ "$lib" == *"/stubs/"* ]]; then
        continue
    fi
    # Only patch actual library files (not symlinks)
    if [[ -f "$lib" ]] && [[ "$lib" =~ \.so\. ]]; then
        echo "Fixing RPATH for: $lib"
        # First, check current RPATH
        current_rpath=$(patchelf --print-rpath "$lib" 2>/dev/null || echo "")
        echo "Current RPATH: '$current_rpath'"
        
        # Remove all RPATH entries by setting empty RPATH first
        patchelf --set-rpath '' "$lib" 2>/dev/null || true
        patchelf --remove-rpath "$lib" 2>/dev/null || true
        
        # Set strict RPATH to $ORIGIN only
        patchelf --set-rpath '$ORIGIN' --force-rpath "$lib" 2>/dev/null || true
        
        # Verify the new RPATH
        new_rpath=$(patchelf --print-rpath "$lib" 2>/dev/null || echo "")
        echo "New RPATH: '$new_rpath'"
    fi
done

check-glibc "$PREFIX"/lib*/*.so.* "$PREFIX"/bin/* "$PREFIX"/targets/*/lib*/*.so.* "$PREFIX"/targets/*/bin/*
