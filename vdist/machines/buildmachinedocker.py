import logging

import docker
from docker.utils import kwargs_from_env

from vdist.machines.buildmachine import BuildMachine


class BuildMachineDocker(BuildMachine):

    def __init__(self, flavor):
        self.logger = logging.getLogger('BuildMachineDocker')

        BuildMachine.__init__(self, flavor)
        self.dockerclient = docker.Client(**kwargs_from_env())
        self.container = None

    def _image_exists(self, image):
        for img in self.dockerclient.images():
            if image in img['RepoTags']:
                return True
        return False

    def _pull_image(self, image):
        self.dockerclient.pull(image)

    def launch(self, build_dir):
        if not self._image_exists(self.flavor):
            self.logger.info(
                'Image does not exist: %s, pulling from repo..' % self.flavor)
            self._pull_image(self.flavor)

        self.logger.info('Starting container: %s' % self.flavor)
        self.container = self.dockerclient.create_container(
            image=self.flavor,
            command='/build/buildscript.sh')
        self.dockerclient.start(
            container=self.container.get('Id'),
            binds={build_dir: '/build'})
        lines = self.dockerclient.logs(container=self.container.get('Id'),
                                       stdout=True, stderr=True, stream=True)
        for line in lines:
            print line

    def shutdown(self):
        self.dockerclient.stop(container=self.container.get('Id'))
        self.dockerclient.remove_container(container=self.container.get('Id'))
