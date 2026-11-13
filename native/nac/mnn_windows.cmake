# The official ZIP is 270 MB. Fetch just the two deflated Release/Dynamic/MD entries.
set(mnn_zip "https://github.com/alibaba/MNN/releases/download/3.6.2/mnn_3.6.2_windows_x64_cpu_opencl_vulkan_avx512.zip")
function(mnn_windows_file name start end packed_hash hash)
    set(output "${mnn_dir}/${name}")
    if(EXISTS "${output}")
        file(SHA256 "${output}" existing_hash)
        if(existing_hash STREQUAL hash)
            return()
        endif()
    endif()
    file(DOWNLOAD "${mnn_zip}" "${output}.deflate" RANGE_START ${start} RANGE_END ${end}
        EXPECTED_HASH "SHA256=${packed_hash}" TLS_VERIFY ON TIMEOUT 180)
    set(inflate [=[
        $ErrorActionPreference = 'Stop'
        $source = [IO.File]::OpenRead($env:KANADE_MNN_PACKED)
        try {
            $decoded = [IO.Compression.DeflateStream]::new(
                $source, [IO.Compression.CompressionMode]::Decompress)
            try {
                $target = [IO.File]::Create($env:KANADE_MNN_OUTPUT)
                try { $decoded.CopyTo($target) }
                finally { $target.Dispose() }
            } finally { $decoded.Dispose() }
        } finally { $source.Dispose() }
    ]=])
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -E env
            "KANADE_MNN_PACKED=${output}.deflate" "KANADE_MNN_OUTPUT=${output}"
            powershell.exe -NoProfile -NonInteractive -Command "${inflate}"
        COMMAND_ERROR_IS_FATAL ANY)
    file(SHA256 "${output}" actual_hash)
    if(NOT actual_hash STREQUAL hash)
        message(FATAL_ERROR "Unexpected hash for ${name}")
    endif()
endfunction()

mnn_windows_file(MNN.dll 59027 3319428
    3f826e56d0056d8a0190f1da6c27b4192e03d8302935990986a7b24f3a36341c
    696936d76807911219f0567ad138cc416bdf71eaf722a0abcd7228114da3b27b)
mnn_windows_file(MNN.lib 3319540 3419531
    cd9fcf6a7c2b8aa629470f0ac43e0c943b4686b637ee107b7fe030683f6f2157
    59b624c3eedd41fe76964f9c10f9d6e1e24cbd9cafc87fd3db34249af3f028e3)
