##### build stage ##############################################################

ARG TARGET_ARCHITECTURE
ARG BASE=23.3.1

FROM  ghcr.io/epics-containers/epics-base-${TARGET_ARCHITECTURE}-developer:${BASE} AS developer

# IOC-TEMPLATE-TODO apt-get install additional build time dependencies
RUN apt-get update && apt-get upgrade -y && \
 apt-get install -y --no-install-recommends \
 libboost-all-dev \
 libxext-dev

# override of epics-base ctools and ibek may be practical but should be removed
# when epics-base is updated
COPY ctools /ctools/
RUN pip install ibek==0.9.5.b2 telnetlib3
# copy the global ibek files
COPY ibek-defs/_global /ctools/_global/

# IOC-TEMPLATE-TODO select the support modules you need
# get and build depdency support modules, for each also copy associated ibek defs

COPY ibek-defs/asyn/ /ctools/asyn/
RUN python3 modules.py install ASYN R4-42 github.com/epics-modules/asyn.git --patch asyn/asyn.sh
RUN make -C ${SUPPORT}/asyn -j $(nproc)

COPY ibek-defs/autosave/ /ctools/autosave/
RUN python3 modules.py install AUTOSAVE R5-10-2 github.com/epics-modules/autosave.git --patch autosave/autosave.sh
RUN make -C ${SUPPORT}/autosave -j $(nproc)

COPY ibek-defs/busy/ /ctools/busy/
RUN python3 modules.py install BUSY R1-7-3 github.com/epics-modules/busy.git
RUN make -C ${SUPPORT}/busy -j $(nproc)

COPY ibek-defs/adsupport/ /ctools/adsupport/
RUN python3 modules.py install ADSUPPORT R1-10 github.com/areaDetector/adsupport.git --patch adsupport/adsupport.sh
RUN make -C ${SUPPORT}/adsupport -j $(nproc)

COPY ibek-defs/adcore/ /ctools/adcore/
RUN python3 modules.py install ADCORE R3-12-1 github.com/areaDetector/adcore.git --patch adcore/adcore.sh
RUN make -C ${SUPPORT}/adcore -j $(nproc)

COPY ibek-defs/adurl/ /ctools/adurl/
RUN python3 modules.py install ADURL R2-3 github.com/areaDetector/adurl.git --patch adurl/adurl.sh
RUN make -C ${SUPPORT}/adurl -j $(nproc)

# add the generic IOC source code. TODO: this will be generated by ibek in future
COPY ioc ${IOC}
# build generic IOC
RUN make -C ${IOC} && make clean -C ${IOC}

##### runtime preparation stage ################################################

FROM developer AS runtime_prep

# get the products from the build stage and reduce to runtime assets only
WORKDIR /min_files
RUN bash /ctools/minimize.sh ${IOC} $(ls -d ${SUPPORT}/*/) /ctools

##### runtime stage ############################################################

FROM ghcr.io/epics-containers/epics-base-${TARGET_ARCHITECTURE}-runtime:${BASE} AS runtime

# these installs required for RTEMS only
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    telnet netcat psmisc libxext6 \
    && rm -rf /var/lib/apt/lists/*

# add products from build stage
COPY --from=runtime_prep /min_files /
COPY --from=developer /venv /venv

# add ioc scripts
COPY ioc ${IOC}

ENV TARGET_ARCHITECTURE ${TARGET_ARCHITECTURE}

ENTRYPOINT ["/bin/bash", "-c", "${IOC}/start.sh"]
