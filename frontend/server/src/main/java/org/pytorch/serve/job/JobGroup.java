package org.pytorch.serve.job;

import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingDeque;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class JobGroup {
    private static final Logger logger = LoggerFactory.getLogger(JobGroup.class);
    String groupId;
    LinkedBlockingDeque<Job> jobs;
    long groupMaxIdleMSec;
    int maxJobQueueSize;
    AtomicLong timestampLastJob;
    AtomicBoolean groupHasNextInput;
    ScheduledExecutorService scheduledExecutorService;

    public JobGroup(String groupId, long groupMaxIdleMSec, int maxJobQueueSize) {
        this.groupId = groupId;
        this.groupMaxIdleMSec = groupMaxIdleMSec;
        this.maxJobQueueSize = maxJobQueueSize;
        this.jobs = new LinkedBlockingDeque<>(maxJobQueueSize);
        this.groupHasNextInput = new AtomicBoolean(true);
        this.scheduledExecutorService = Executors.newSingleThreadScheduledExecutor();
    }

    public boolean appendJob(Job job) {
        if (!groupHasNextInput()) {
            logger.error(
                    "Failed to add requestId: {} in sequence: {} due to expiration",
                    job.getJobId(),
                    groupId);
            return false;
        } else if (jobs.offer(job)) {
            if (this.timestampLastJob == null) {
                this.timestampLastJob = new AtomicLong(System.currentTimeMillis());
            } else {
                this.timestampLastJob.set(System.currentTimeMillis());
            }
            return true;
        }

        logger.error(
                "Skip the requestId: {} in sequence: {} due to exceeding maxJobQueueSize: {}",
                job.getJobId(),
                groupId,
                maxJobQueueSize);
        return false;
    }

    public Job pollJob(long timeout) {
        try {
            return jobs.poll(timeout, TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            logger.error("Failed to poll a job from group {}", groupId, e);
        }
        return null;
    }

    public void monitorGroupIdle() {
        Runnable task =
                () -> {
                    if (!groupHasNextInput.get()) {
                        return;
                    }

                    if (System.currentTimeMillis() - timestampLastJob.get() > groupMaxIdleMSec) {
                        groupHasNextInput.set(false);
                        logger.warn(
                                "Job group {} has no input in the past {} msec and set hasNextInput as false",
                                groupId,
                                groupMaxIdleMSec);
                    }
                };
        this.scheduledExecutorService.scheduleWithFixedDelay(
                task, 0, groupMaxIdleMSec, TimeUnit.MILLISECONDS);
    }

    public void monitorShutdown() {
        this.scheduledExecutorService.shutdown();
        logger.info("JobGroup: {} monitor was shutdown", groupId);
    }

    public void setGroupHasNextInput(boolean groupHasNextInput) {
        this.groupHasNextInput.set(groupHasNextInput);
    }

    public boolean groupHasNextInput() {
        return this.groupHasNextInput.get();
    }

    public String getGroupId() {
        return groupId;
    }

    public int size() {
        return jobs.size();
    }
}