# overlay-env

Docker image based on [aegypius/gentoo](https://registry.hub.docker.com/u/aegypius/gentoo/)
base image with a portage tree.

The main purpose of this image is to provide containers to test ebuild development
on a vanilla gentoo environment.

### Standalone usage

    cd /path/to/my/overlay
    docker pull aegypius/overlay-env
    docker run -v$(pwd):/overlay -i -t aegypius/overlay-env

### Creates your image from this base

You can create your own image with custom package installed and use docker cache
to be used with dependencies:

    FROM aegypius/overlay-env

    # Install a proper editor
    RUN emerge -v vim

    # Install dependencies for my ebuild only
    RUN emerge --onlydeps dev-util/my-ebuild

### Tips & Tricks

 - You can provide your aliases or custom bash commands by creating a simple .bashrc file
  in the mounted directory.

  Exemple:

       cd /path/to/my/overlay
       echo 'alias ll="ls -lh --color=auto"' > .bashrc
       docker run -v$(pwd):/overlay -i -t aegypius/overlay-env
       768ba2b131ee overlay # ll
       total 8.0K
       -rw-rw-r-- 1 1000 users 1.5K Jul 26 13:34 Dockerfile
       -rw-rw-r-- 1 1000 users  397 Jul 26 13:25 README.md

---
### Contributing

Contributions are welcome, please submit issues, pull-requests on [github](https://github.com/aegypius/docker-gentoo)...
