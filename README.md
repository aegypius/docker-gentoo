# docker-gentoo

The purpose of this repository is to provide a way to
get an updated gentoo base container

### aegypius/gentoo base image

The base image is based on a simple stage3 tarball build with [danthedispatcher](https://github.com/danthedispatcher/docker-mkimage-gentoo)
script build and upload to the registry using [wercker](https//wercker.com).

There is no portage tree in this build to reduce image size.

You can check everything from ```wercker.yml``` file


### aegypius/overlay-env

This is a trusted build for docker registry.

Overlay environment with a portage tree and an overlay volume to hack in a vanilla
installation. [Additional informations](overlay-env/README.md)


---
[![wercker status](https://app.wercker.com/status/aabb3ae3a97ad0f059f1ed149445dd5f/s "wercker status")](https://app.wercker.com/project/bykey/aabb3ae3a97ad0f059f1ed149445dd5f)
