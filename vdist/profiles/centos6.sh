#!/bin/bash -x
PYTHON_VERSION="{{python_version}}"
PYTHON_BASEDIR="{{python_basedir}}"

# Fail on error
set -e


{% if build_deps %}
# Refresh repositories list to avoid problems with too old databases.
yum update -y
# Install build dependencies.
yum install -y {{build_deps|join(' ')}}
{% endif %}

# Install prerequisites
## TODO: Try to comment this. I think we don't need it any longer.
# easy_install virtualenv

{% if compile_python %}
# Download and compile what is going to be the Python we are going to use
# as our portable python environment.
    # Since Python 3.7 you need libffi to compile it.
    yum update --nogpgcheck -y
    yum install libffi-devel -y
    cd /var/tmp
    curl -O https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz
    tar xzvf Python-$PYTHON_VERSION.tgz
    cd Python-$PYTHON_VERSION
    # Configure fails if folder in rpath doesn't exists before.
    # Creating it, even empty, before configure seems to solve issue.
    # More info in:
    #   http://koansys.com/tech/building-python-with-enable-shared-in-non-standard-location
    mkdir -p ${PYTHON_BASEDIR}/lib
    ./configure --prefix=$PYTHON_BASEDIR --enable-shared LDFLAGS="-Wl,-rpath ${PYTHON_BASEDIR}/lib"
    make
    make altinstall
    PYTHON_MAIN_VERSION=${PYTHON_VERSION:0:3}
    if [[ ${PYTHON_VERSION:0:1} == "2" ]]; then
        ln -s $PYTHON_BASEDIR/bin/python$PYTHON_MAIN_VERSION $PYTHON_BASEDIR/bin/python
        # At this point pip does not exists yet so we're creating a dead link
        # but later we are going to install pip through ensurepip module
        # so this is going to be fixed.
        ln -s $PYTHON_BASEDIR/bin/pip$PYTHON_MAIN_VERSION $PYTHON_BASEDIR/bin/pip
    else
        ln -s $PYTHON_BASEDIR/bin/python$PYTHON_MAIN_VERSION $PYTHON_BASEDIR/bin/python3
        ln -s $PYTHON_BASEDIR/bin/pip$PYTHON_MAIN_VERSION $PYTHON_BASEDIR/bin/pip3
    fi
{% endif %}

# Create temporary folder to place our application files.
if [ ! -d {{package_tmp_root}} ]; then
    mkdir -p {{package_tmp_root}}
fi

cd {{package_tmp_root}}

{% if source.type == 'git' %}
    # Place application files inside temporary folder after dowloading it from
    # git repository.
    git clone {{source.uri}}
    cd {{project_root}}
    git checkout {{source.branch}}

{% elif source.type in ['directory', 'git_directory'] %}
    # Place application files inside temporary folder after copying it from
    # local folder.
#    mkdir -p {{project_root}}
#    cd {{project_root}}
    cp -ar {{shared_dir}}/{{scratch_folder_name}}/{{project_root}} .
    cd {{package_tmp_root}}/{{project_root}}

    {% if source.type == 'git_directory' %}
        git checkout {{source.branch}}
    {% endif %}

{% else %}

    echo "invalid source type, exiting."
    exit 1

{% endif %}

{% if use_local_pip_conf %}
    cp -r {{scratch_dir}}/.pip ~
{% endif %}

{% if working_dir %}
    # When working_dir is set, assume that is the base and remove the rest
    mv {{working_dir}} {{package_tmp_root}} && rm -rf {{package_tmp_root}}/{{project_root}}
    cd {{package_tmp_root}}/{{working_dir}}

    # Reset project_root.
    {% set project_root = working_dir %}
{% endif %}

# We are going to remove any traces of a previous virtualenv that we could
# have imported with project, to keep things clean.
## TODO: Give it a second thought. It's odd to have virtualenv folders in a
## code repository. Whereas you may have a folder called "lib" or "bin" that
## you may want to package but it doesn't come from a virtualenv. Maybe we
## should remove next line in a further revision.
# rm -rf bin include lib local

# To install our application and dependencies inside our portable python
# environment we have to run setup.py and download from Pypi using our
# portable python environment "python" and "pip" executables.
if [[ ${PYTHON_VERSION:0:1} == "2" ]]; then
    PYTHON_BIN="$PYTHON_BASEDIR/bin/python"
    PIP_BIN="$PYTHON_BASEDIR/bin/pip"
    $PYTHON_BIN -m ensurepip
else
    PYTHON_BIN="$PYTHON_BASEDIR/bin/python3"
    PIP_BIN="$PYTHON_BASEDIR/bin/pip3"
fi

# Install package python dependencies inside our portable python environment.
if [ -f "$PWD{{requirements_path}}" ]; then
    $PIP_BIN install -U pip setuptools
    $PIP_BIN install {{pip_args}} -r $PWD{{requirements_path}}
fi

# If we have an installer, install our application inside our portable python
# environment.
if [ -f "setup.py" ]; then
    $PYTHON_BIN setup.py install
    setup=true
else
    setup=false
fi

cd /

# Get rid of VCS info.
find {{package_tmp_root}} -type d -name '.git' -print0 | xargs -0 rm -rf
find {{package_tmp_root}} -type d -name '.svn' -print0 | xargs -0 rm -rf

# If setup==true then we have installed our application inside our portable python
# environment, so we package that environment.
if $setup; then
    {% if custom_filename %}
        fpm -s dir -t rpm -n {{app}} -p {{package_tmp_root}}/{{custom_filename}} -v {{version}} {% for dep in runtime_deps %} --depends {{dep}} {% endfor %} {{fpm_args}} $PYTHON_BASEDIR
    {% else %}
        fpm -s dir -t rpm -n {{app}} -p {{package_tmp_root}} -v {{version}} {% for dep in runtime_deps %} --depends {{dep}} {% endfor %} {{fpm_args}} $PYTHON_BASEDIR
    {% endif %}
    cp {{package_tmp_root}}/*rpm {{shared_dir}}/.
# If setup==false then our application is in a different folder than our
# portable python environment. So we package both: our application folder and
# the one with our python package environment. In this case packager should use
# packaging scripts to create proper links and launchers at installation side so
# application is launched using the packaged python environment.
else
    mkdir -p {{package_install_root}}/{{app}}
    cp -r {{package_tmp_root}}/{{app}}/* {{package_install_root}}/{{app}}/.
    {% if custom_filename %}
        fpm -s dir -t rpm -n {{app}} -p {{package_tmp_root}}/{{custom_filename}} -v {{version}} {% for dep in runtime_deps %} --depends {{dep}} {% endfor %} {{fpm_args}} {{package_install_root}}/{{project_root}} $PYTHON_BASEDIR
    {% else %}
        fpm -s dir -t rpm -n {{app}} -p {{package_tmp_root}} -v {{version}} {% for dep in runtime_deps %} --depends {{dep}} {% endfor %} {{fpm_args}} {{package_install_root}}/{{project_root}} $PYTHON_BASEDIR
    {% endif %}
    cp {{package_tmp_root}}/*rpm {{shared_dir}}/.
fi

chown -R {{local_uid}}:{{local_gid}} {{shared_dir}}
