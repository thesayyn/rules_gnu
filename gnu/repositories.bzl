"""Declare runtime dependencies

These are needed for local dev, and users must install them as well.
See https://docs.bazel.build/versions/main/skylark/deploying.html#dependencies
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", _http_archive = "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//gnu/private:toolchains_repo.bzl", "PLATFORMS", "toolchains_repo")
load("//gnu/private:versions.bzl", "TOOL_VERSIONS")

def http_archive(name, **kwargs):
    maybe(_http_archive, name = name, **kwargs)

# WARNING: any changes in this function may be BREAKING CHANGES for users
# because we'll fetch a dependency which may be different from one that
# they were previously fetching later in their WORKSPACE setup, and now
# ours took precedence. Such breakages are challenging for users, so any
# changes in this function should be marked as BREAKING in the commit message
# and released only in semver majors.
# This is all fixed by bzlmod, so we just tolerate it for now.
def rules_gnu_dependencies():
    # The minimal version of bazel_skylib we require
    http_archive(
        name = "bazel_skylib",
        sha256 = "74d544d96f4a5bb630d465ca8bbcfe231e3594e5aae57e1edbf17a6eb3ca2506",
        urls = [
            "https://github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
            "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
        ],
    )

########
# Remaining content of the file is only used to support toolchains.
########
_DOC = "Fetch external tools needed for gnu toolchain"
_ATTRS = {
    "gnu_version": attr.string(mandatory = True, values = TOOL_VERSIONS.keys()),
    "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
}

def _gnu_repo_impl(repository_ctx):
    url = "https://github.com/someorg/someproject/releases/download/v{0}/gnu-{1}.zip".format(
        repository_ctx.attr.gnu_version,
        repository_ctx.attr.platform,
    )
    repository_ctx.download_and_extract(
        url = url,
        integrity = TOOL_VERSIONS[repository_ctx.attr.gnu_version][repository_ctx.attr.platform],
    )
    build_content = """#Generated by gnu/repositories.bzl
load("@rules_gnu//gnu:toolchain.bzl", "gnu_toolchain")
gnu_toolchain(name = "gnu_toolchain", target_tool = select({
        "@bazel_tools//src/conditions:host_windows": "gnu_tool.exe",
        "//conditions:default": "gnu_tool",
    }),
)
"""

    # Base BUILD file for this repository
    repository_ctx.file("BUILD.bazel", build_content)

gnu_repositories = repository_rule(
    _gnu_repo_impl,
    doc = _DOC,
    attrs = _ATTRS,
)

# Wrapper macro around everything above, this is the primary API
def gnu_register_toolchains(name, register = True, **kwargs):
    """Convenience macro for users which does typical setup.

    - create a repository for each built-in platform like "gnu_linux_amd64" -
      this repository is lazily fetched when node is needed for that platform.
    - TODO: create a convenience repository for the host platform like "gnu_host"
    - create a repository exposing toolchains for each platform like "gnu_platforms"
    - register a toolchain pointing at each platform
    Users can avoid this macro and do these steps themselves, if they want more control.
    Args:
        name: base name for all created repos, like "gnu1_14"
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
        **kwargs: passed to each node_repositories call
    """
    for platform in PLATFORMS.keys():
        gnu_repositories(
            name = name + "_" + platform,
            platform = platform,
            **kwargs
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
    )
