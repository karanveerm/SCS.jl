using BinaryProvider, Libdl # requires BinaryProvider 0.3.0 or later

## NOTE: This is not a typical build.jl file; it has extra stuff toward the bottom.
## Don't just replace this file with the output of a BinaryBuilder repository!

# Parse some basic command-line arguments
const verbose = "--verbose" in ARGS
const prefix = Prefix(get([a for a in ARGS if a != "--verbose"], 1, joinpath(@__DIR__, "usr")))
products = [
    LibraryProduct(prefix, ["libscsindir"], :indirect),
    LibraryProduct(prefix, ["libscsdir"], :direct),
]

# Download binaries from hosted location
bin_prefix = "https://github.com/JuliaOpt/SCSBuilder/releases/download/v2.1.1"

# Listing of files generated by BinaryBuilder:
download_info = Dict(
    Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.aarch64-linux-gnu-gcc4.tar.gz", "efa3f206ceee91221e4e78f079b246a4bf04d3a3888c25f92212b0525dd30ba5"),
    Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.aarch64-linux-gnu-gcc7.tar.gz", "644c6d05a7e9b42a3a4b7ee150b6e6ac39c6f606b2ea54d3c2e051d022411186"),
    Linux(:aarch64, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.aarch64-linux-gnu-gcc8.tar.gz", "807ef6d29d3bd1c4d2091b73c8a027d554962a645ecb8f459ff01900cf54867c"),
    Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.aarch64-linux-musl-gcc4.tar.gz", "0f665094019547ec969b67b34d1117b832556412f6ff8f18e590418b9ce5d0a8"),
    Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.aarch64-linux-musl-gcc7.tar.gz", "3828c39e13ba798a3adb9001ae0d6e3323bcc618eadb9010ee278dd3278cbb9e"),
    Linux(:aarch64, libc=:musl, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.aarch64-linux-musl-gcc8.tar.gz", "bb3d0440c00b82866a3d5604bad05c817fa3af142640ccea33d5e2d0bf3d2519"),
    Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.arm-linux-gnueabihf-gcc4.tar.gz", "62be85de04e317d35a4c6c1f840beb2a3b15f4b6edb0a39029b188cd9e260629"),
    Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.arm-linux-gnueabihf-gcc7.tar.gz", "79d2dee9a96a5a5c951e872a446418a674b8b4e21591a703b49f9abb26fc406c"),
    Linux(:armv7l, libc=:glibc, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.arm-linux-gnueabihf-gcc8.tar.gz", "fb69a2ed44d6660fe63b69d0de7903def16d4722039ce8d824b09d6d8b85377e"),
    Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.arm-linux-musleabihf-gcc4.tar.gz", "aac19b6bf3fa76ca45222c444c22a14d8490574e7799c2b7aa3ba2cf71f98fc1"),
    Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.arm-linux-musleabihf-gcc7.tar.gz", "cb1c1d43a94ef64989ad1f1435f434e301fce34456460f15be9e12aebe3e3f77"),
    Linux(:armv7l, libc=:musl, call_abi=:eabihf, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.arm-linux-musleabihf-gcc8.tar.gz", "b9e1750ddee2c5656392cfbe6b404ddb59424cdd27465d900115d15a8e5d55d0"),
    Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-linux-gnu-gcc4.tar.gz", "b2037f11882d7f235db0f3bba6a389e9e3e5572d203fcf6d7ad66d60f56277fc"),
    Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-linux-gnu-gcc7.tar.gz", "35e62f74f7b18e1be049034652e7df9b45d90d37b359235d92272c7bee048765"),
    Linux(:i686, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-linux-gnu-gcc8.tar.gz", "f90c507ff44a15e616e29e48f086490aaff760b7a51d4d561f911acbadb40b10"),
    Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-linux-musl-gcc4.tar.gz", "16fe6fa8e88e936e94192fb44087d1c343c647bf43fbd5f4251d3cb0259141e5"),
    Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-linux-musl-gcc7.tar.gz", "44450b4988fdb4f080f4a9b071d060baac52efc6baba866b2a761b5caecf2613"),
    Linux(:i686, libc=:musl, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-linux-musl-gcc8.tar.gz", "1d5062082513cba12190b0effe2dc6a6fd30af6ada9d807a47c284ba7a7e405d"),
    Windows(:i686, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-w64-mingw32-gcc4.tar.gz", "0f95846227aa05bed9d9f26812acedb971e7218b039d7d582db89b460c0341c7"),
    Windows(:i686, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-w64-mingw32-gcc7.tar.gz", "c616da0cf404d380db9daf7ce121034356ff491450d828a0455b97a1c1547126"),
    Windows(:i686, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.i686-w64-mingw32-gcc8.tar.gz", "d6ee325284380c649fba0542b4944e7740e13283534e81821389b2f11a611343"),
    Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.powerpc64le-linux-gnu-gcc4.tar.gz", "9ee5271d0ba21d2a32ac4f9cafb18e99a9d4368ac2168aa46de6e8a4a84ab124"),
    Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.powerpc64le-linux-gnu-gcc7.tar.gz", "c3a5ca3927e45b901a236fa85fe40698b7e48fcb6cd54f4f579cbe5dfa872e61"),
    Linux(:powerpc64le, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.powerpc64le-linux-gnu-gcc8.tar.gz", "3312be93587958a06627b666d54098b1cb0cff5ede5eaa5e58815119677f2d02"),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-apple-darwin14-gcc4.tar.gz", "4d93317beabcca07eda24b29c6eb35f0b2682b344b1b4bfc56bea47d9ee13fde"),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-apple-darwin14-gcc7.tar.gz", "3a32c772aa6949e17e86875ba954b35af36f279681225397d0f8f8730809f437"),
    MacOS(:x86_64, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-apple-darwin14-gcc8.tar.gz", "71f8855929052bd43a1e9243cc952ed0cf599220397a66ca0cb06c5f4afa1b6d"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-linux-gnu-gcc4.tar.gz", "a23ded4138c1076508e414ebd278907de4608899d65b40696662dccd3ae30055"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-linux-gnu-gcc7.tar.gz", "7b9df657c8729e7bcc8dda8a3deb18c2ff949eae373e6096ebedc5ad788824c4"),
    Linux(:x86_64, libc=:glibc, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-linux-gnu-gcc8.tar.gz", "090a2ac4209353ebe3306e08252ec3e88154e16f57388c8d029aba13babdd95a"),
    Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-linux-musl-gcc4.tar.gz", "8866e9c30cfdff73340f615c7069c63b66ae25a33395315e59d228d33bc241ca"),
    Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-linux-musl-gcc7.tar.gz", "2657f43f8844f9696fec493e64b96768b3f7afa7cca6babf8c2a25a28d871ea4"),
    Linux(:x86_64, libc=:musl, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-linux-musl-gcc8.tar.gz", "33658481f0b5fc260a38ddc847f046e5aa0f26824cc783bd7a9b81dbe8c779cd"),
    FreeBSD(:x86_64, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-unknown-freebsd11.1-gcc4.tar.gz", "f96a3f7ed7d1dc39f47c30b8b7005796162ac78443b27c96c02b87158964d9a6"),
    FreeBSD(:x86_64, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-unknown-freebsd11.1-gcc7.tar.gz", "3a7ccb36853ded8e4c90af7efc4aeae87d8e8f329b158f5a503699912e94be39"),
    FreeBSD(:x86_64, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-unknown-freebsd11.1-gcc8.tar.gz", "5a58cca92e50498c576e4e3b2ff0c21f2e4d7bfc0b90050a9a4884db69eb9b00"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc4)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-w64-mingw32-gcc4.tar.gz", "4d2d9f6d6cedf2a7905cfd06aabf598270081380830f07b7cca466342b13990f"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc7)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-w64-mingw32-gcc7.tar.gz", "35873dd09ee83a114a945b7ccc07b91352c6984e8c6973573423d8483f5917e3"),
    Windows(:x86_64, compiler_abi=CompilerABI(:gcc8)) => ("$bin_prefix/SCSBuilder.v2.1.1.x86_64-w64-mingw32-gcc8.tar.gz", "a169be57d28bc19752d2acbca7e624600820e4865f9035318de6c56d0c1783e8"),
)

this_platform = platform_key_abi()

custom_library = false
if haskey(ENV,"JULIA_SCS_LIBRARY_PATH")

    names_symbols = Dict("libscsdir"=>:direct, "libscsindir"=>:indirect, "libscsgpu"=>:indirectgpu)

    scs_prefix = ENV["JULIA_SCS_LIBRARY_PATH"]
    @assert isdir(scs_prefix)

    custom_products = Product[]
    for fn in readdir(scs_prefix)
        if endswith(fn, Libdl.dlext) && haskey(names_symbols,fn[1:end-3])
            lib = fn[1:end-3]
            push!(custom_products,
                LibraryProduct(scs_prefix, [lib], names_symbols[lib]))
        end
    end

    if all(satisfied(p; verbose=verbose) for p in custom_products)
        products = custom_products
        custom_library = true
    else
        error("Could not install custom libraries from $(ENV["JULIA_SCS_LIBRARY_PATH"]).\nTo fall back to BinaryProvider call delete!(ENV,\"JULIA_SCS_LIBRARY_PATH\") and run build again.")
    end
end

if !custom_library
    # Install unsatisfied or updated dependencies:
    unsatisfied = any(!satisfied(p; verbose=verbose) for p in products)

    dl_info = choose_download(download_info, this_platform)
    if dl_info === nothing && unsatisfied
        # If we don't have a compatible .tar.gz to download, complain.
        # Alternatively, you could attempt to install from a separate provider,
        # build from source or something even more ambitious here.
        error("Your platform (\"$(Sys.MACHINE)\", parsed as \"$(triplet(platform_key_abi()))\") is not supported by this package!")
    end

    # If we have a download, and we are unsatisfied (or the version we're
    # trying to install is not itself installed) then load it up!
    if unsatisfied || !isinstalled(dl_info...; prefix=prefix)
        # Download and install binaries
        install(dl_info...; prefix=prefix, force=true, verbose=verbose)
    end
end

# Write out a deps.jl file that will contain mappings for our products
write_deps_file(joinpath(@__DIR__, "deps.jl"), products, verbose=verbose)
