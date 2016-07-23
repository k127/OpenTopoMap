FROM ubuntu:14.04.4

MAINTAINER Klaus Hartl <k127@gmx.de>

# Install Mapnik renderer:
RUN apt-get update && apt-get install -y --force-yes --no-install-recommends \
	libmapnik2.2 \
	libmapnik2-dev \
	mapnik-utils \
	python-mapnik \
	&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Postgresql database TODO use separate container:
RUN apt-get update && apt-get install -y --force-yes --no-install-recommends \
    postgresql-9.3-postgis-2.1 \
    postgresql-contrib-9.3 \
    postgresql-server-dev-9.3 \
	&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# change default path via symlink:
RUN chown postgres /mnt/database \
    && chgrp postgres /mnt/database \
    && /etc/init.d/postgresql stop \
    && cp -a /var/lib/postgresql/9.3/main /mnt/database \
    && rm -r /var/lib/postgresql/9.3 \
    && ln -s /mnt/database /var/lib/postgresql/9.3 \
    && /etc/init.d/postgresql start

# TODO
# Tweaks:
#       		Edit the file /etc/postgresql/9.3/main/postgresql.conf and make the following changes:
#       			shared_buffers = 128MB
#       			checkpoint_segments = 20
#       			work_mem = 256MB
#       			maintenance_work_mem = 256MB
#       			autovacuum = off
#
#       		As root, edit /etc/sysctl.conf and add these lines near the top after the other “kernel” definitions:
#       			# Increase kernel shared memory segments - needed for large databases
#       			kernel.shmmax=268435456

# Install mod_tile from source
RUN apt-get update && apt-get install -y --force-yes --no-install-recommends \
    subversion \
    git-core \
    tar \
    unzip \
    wget \
    bzip2 \
    build-essential \
    autoconf \
    libtool \
    libxml2-dev \
    libgeos-dev \
    libgeos++-dev \
    libpq-dev \
    libbz2-dev \
    munin-node \
    munin \
    libprotobuf-c0-dev \
    protobuf-c-compiler \
    libfreetype6-dev \
    libpng12-dev \
    libtiff4-dev \
    libicu-dev \
    libgdal-dev \
    libcairo2-dev \
    libcairomm-1.0-dev \
    apache2 \
    apache2-dev \
    libagg-dev \
    lua5.2 \
    liblua5.2-dev \
    ttf-unifont \
	&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir ~/src \
    && cd ~/src \
    && git clone git://github.com/openstreetmap/mod_tile.git \
    && cd mod_tile \
    && ./autogen.sh \
    && ./configure \
    && make \
    && make install \
    && make install-mod_tile \
    && ldconfig

# TODO
#	sudo vi /etc/apache2/mods-enabled/mod_tile.load
#		LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so

# TODO
	# change in file /usr/local/etc/renderd.conf:
	# /usr/local/lib/mapnik/input

# Install osm2pgsql from source
RUN cd ~/src \
    && git clone git://github.com/openstreetmap/osm2pgsql.git \
    && cd osm2pgsql \
    && ./autogen.sh \
    && ./configure \
    && make \
    && make install

# Install osmosis (for diff updates)
RUN apt-get update && apt-get install -y --force-yes --no-install-recommends \
    default-jre-headless \
    junit \
	&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir ~/src/osmosis \
    && cd ~/src/osmosis \
    && wget http://bretth.dev.openstreetmap.org/osmosis-build/osmosis-latest.tgz \
    && tar xvfz osmosis-latest.tgz \
    && chmod a+x bin/osmosis \
    && ln -s bin/osmosis /usr/local/bin/osmosis

# Set up osmosis working dir for daily updates
RUN osmosis --rrii workingDirectory=~/data/updates
	# TODO edit configuration.txt to baseUrl=http://download.geofabrik.de/europe/germany/bayern/mittelfranken-updates/

# Create database gis
RUN createdb gis \
    && psql -d gis -c 'CREATE EXTENSION postgis; CREATE EXTENSION hstore;'

# Load data into database
RUN cd ~/data \
    && wget http://download.geofabrik.de/europe-latest.osm.pbf \
    && cd ~/data/updates \
    && wget http://download.geofabrik.de/europe-updates/state.txt

RUN screen osm2pgsql \
        --slim -d gis -C 12000 --number-processes 10 \
        --flat-nodes /mnt/db/flat-nodes/gis-flat-nodes.bin \
        --style ~/OpenTopoMap/mapnik/osm2pgsql/opentopomap.style \
        ~/data/planet-latest.osm.pbf

# Update data
RUN osmosis --rri workingDirectory=~/data/updates --simplify-change --write-xml-change ~/data/updates/changes.osc.gz \
    && osm2pgsql --append \
        --slim -d gis  -C 12000 --number-processes 10 \
        --flat-nodes ~/data/flat-nodes.bin \
        --style ~/OpenTopoMap/mapnik/osm2pgsql/opentopomap.style \
        ~/data/updates/changes.osc.gz \
    && rm ~/data/updates/changes.osc.gz

# Download OpenTopoMap files
RUN cd ~ \
    && git clone https://github.com/der-stefan/OpenTopoMap.git \
    && cd ~/OpenTopoMap/mapnik

# use the generalized water polygons from http://openstreetmapdata.com/
RUN wget http://data.openstreetmapdata.com/water-polygons-generalized-3857.zip
RUN wget http://data.openstreetmapdata.com/water-polygons-split-3857.zip

	# You need the files for hillshade and contours
	# TODO Please create them on your own. A hint howto proceed is given in HOWTO_DEM

# Configure apache and mod_tile/renderd
	# edit /usr/local/etc/renderd.conf
	# edit /etc/apache2/sites-available/000-default.conf
RUN a2enmod rewrite && service apache2 restart

RUN mkdir /var/run/renderd \
    && chown username /var/run/renderd \
    && renderd -f -c /usr/local/etc/renderd.conf

RUN mkdir /var/lib/mod_tile \
    && chown username /var/lib/mod_tile

# start renderd automatically on every boot:
RUN cp  ~/src/mod_tile/debian/renderd.init /etc/init.d/renderd \
    && chmod u+x /etc/init.d/renderd \
    && ln -s /etc/init.d/renderd /etc/rc2.d/S20renderd

# edit /etc/init.d/renderd:
ENV DAEMON  /usr/local/bin/${NAME}
ENV DAEMON_ARGS "-c /usr/local/etc/renderd.conf"
# TODO
#ENV RUNASUSER   ...

