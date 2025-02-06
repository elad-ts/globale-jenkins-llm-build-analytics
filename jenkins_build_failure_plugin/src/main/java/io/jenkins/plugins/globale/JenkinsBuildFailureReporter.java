package io.jenkins.plugins.globale;

import hudson.Extension;
import hudson.model.*;
import hudson.model.listeners.RunListener;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;
import jenkins.model.GlobalConfiguration;
import jenkins.model.Jenkins;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@Extension
public class JenkinsBuildFailureReporter extends RunListener<Run<?, ?>> {
    private static final Logger logger = Logger.getLogger(JenkinsBuildFailureReporter.class.getName());

    // Replace these with your bucket name and key prefix
    private static final String BUCKET_NAME = "jenkins-logs-ai";
    private static final String KEY_PREFIX = "jenkins-logs/";

    private final S3Client s3Client = S3Client.create();

    @Override
    public void onCompleted(Run<?, ?> run, TaskListener listener) {
        JenkinsBuildFailureReporterConfig config = GlobalConfiguration.all().get(JenkinsBuildFailureReporterConfig.class);

        if (config != null && config.isProjectIncluded(run.getParent().getName())) {
            try {
                String report = generateReport(run, listener);
                String key = KEY_PREFIX + run.getParent().getName() + "/" + run.getId() + "-report.txt";
                uploadToS3(key, report);
            } catch (Exception e) {
                logger.log(Level.SEVERE, "Error while generating report for job: {0}", run.getDisplayName());
            }
        } else {
            logger.log(
                    Level.INFO,
                    "Project {0} is not included for report generation.",
                    run.getParent().getName());
        }
    }

    private String generateReport(Run<?, ?> run, TaskListener listener) throws Exception {
        StringBuilder report = new StringBuilder();
        report.append("Job Report:\n");
        report.append("- Job Name: " + run.getParent().getName() + "\n");
        report.append("- Build ID: " + run.getId() + "\n");
        report.append("- Status: " + getStatus(run) + "\n");
        report.append("- Logs:\n" + getJobLogs(run) + "\n");
        report.append("- Triggered By: " + getTriggeredBy(run) + "\n");
        report.append("- Code:\n" + getInstructions(run) + "\n");
        report.append("- SCM Info:\n" + getSCMInfo(run) + "\n");
        report.append("- Parameters:\n" + getParameters(run) + "\n");
        report.append("- Environment Variables:\n" + getEnvironmentVariables(run, listener) + "\n");
        report.append("- Health Score:\n" + getHealthScore(run.getParent()) + "\n");
        report.append("- Upstream Job:\n" + getUpstreamJobInfo(run) + "\n");
        report.append("- Retry Attempts: " + getRetryAttempts(run) + "\n");
        report.append("- Concurrent Builds on Same Node: " + getConcurrentBuilds(run) + "\n");
        report.append("- Build Queue Time: " + getBuildQueueTime(run) + " seconds\n");
        return report.toString();
    }

    private String getJobLogs(Run<?, ?> run) {
        StringBuilder logContent = new StringBuilder();
        try {
            run.getLog(100).forEach(line -> logContent.append(line).append("\n"));
        } catch (IOException e) {
            throw new RuntimeException(e);
        }

        return logContent.toString();
    }

    private String getStatus(Run<?, ?> run) {
        return run.getResult() != null ? run.getResult().toString() : "UNKNOWN";
    }

    private String getTriggeredBy(Run<?, ?> run) {
        StringBuilder triggeredBy = new StringBuilder();
        run.getCauses().forEach(cause -> {
            if (cause instanceof Cause.UserIdCause) {
                triggeredBy.append(((Cause.UserIdCause) cause).getUserId());
            } else {
                triggeredBy.append(cause.getShortDescription());
            }
        });
        return triggeredBy.toString();
    }

    private String getInstructions(Run<?, ?> run) {

        if (run.getParent() instanceof FreeStyleProject) {
            return getFreestyleSteps(run);
        } else {
            return getPipelineCode(run);
        }
    }

    private String getSCMInfo(Run<?, ?> run) {
        StringBuilder scmInfo = new StringBuilder("[");
        if (run instanceof org.jenkinsci.plugins.workflow.job.WorkflowRun) {
            org.jenkinsci.plugins.workflow.job.WorkflowRun workflowRun =
                    (org.jenkinsci.plugins.workflow.job.WorkflowRun) run;
            workflowRun.getSCMs().forEach(scm -> {
                scmInfo.append("{\"scmKey\": \"" + scm.getKey() + "\"},");
            });
        }
        if (scmInfo.charAt(scmInfo.length() - 1) == ',') {
            scmInfo.deleteCharAt(scmInfo.length() - 1);
        }
        scmInfo.append("]");
        return scmInfo.toString();
    }

    private String getParameters(Run<?, ?> run) {
        StringBuilder parameters = new StringBuilder("[");
        List<ParametersAction> actions = run.getActions(ParametersAction.class);
        for (ParametersAction action : actions) {
            action.getParameters().forEach(param -> {
                parameters.append("{\"name\": \"" + param.getName() + "\", \"value\": \"" + param.getValue() + "\"},");
            });
        }
        if (parameters.charAt(parameters.length() - 1) == ',') {
            parameters.deleteCharAt(parameters.length() - 1);
        }
        parameters.append("]");
        return parameters.toString();
    }

    private int getRetryAttempts(Run<?, ?> run) {
        // Placeholder logic: Retrieve retry attempts from the build context or metadata
        int retries = 0;
        Run<?, ?> previousRun = run.getPreviousBuild();
        while (previousRun != null && previousRun.getResult() != Result.SUCCESS) {
            retries++;
            previousRun = previousRun.getPreviousBuild();
        }
        return retries;
    }

    private int getConcurrentBuilds(Run<?, ?> run) {
        int concurrentBuilds = 0;
        Computer computer = run.getExecutor().getOwner();
        for (Executor executor : computer.getExecutors()) {
            if (executor.getCurrentExecutable() != null && executor.getCurrentExecutable() != run) {
                concurrentBuilds++;
            }
        }
        return concurrentBuilds;
    }

    private String getEnvironmentVariables(Run<?, ?> run, TaskListener listener) throws Exception {
        StringBuilder envVars = new StringBuilder("{");
        Map<String, String> env = run.getEnvironment(listener);
        env.forEach((key, value) -> envVars.append("\"" + key + "\": \"" + value + "\", "));
        if (envVars.charAt(envVars.length() - 2) == ',') {
            envVars.deleteCharAt(envVars.length() - 2);
        }
        envVars.append("}");
        return envVars.toString();
    }

    private String getHealthScore(Job<?, ?> job) {
        if (job != null) {
            HealthReport healthReport = job.getBuildHealth();
            return "{\"score\": " + healthReport.getScore() + ", \"description\": \"" + healthReport.getDescription()
                    + "\"}";
        }
        return "{}";
    }

    private String getUpstreamJobInfo(Run<?, ?> run) {
        Cause.UpstreamCause upstreamCause = run.getCause(Cause.UpstreamCause.class);
        if (upstreamCause != null) {
            return "{\"upstreamProject\": \"" + upstreamCause.getUpstreamProject() + "\", \"upstreamBuild\": "
                    + upstreamCause.getUpstreamBuild() + "}";
        }
        return "{}";
    }

    private void uploadToS3(String key, String content) {
        // TODO:: eladh - make it generic by suppling restul api
        try {
            PutObjectRequest putRequest =
                    PutObjectRequest.builder().bucket(BUCKET_NAME).key(key).build();
            s3Client.putObject(
                    putRequest,
                    software.amazon.awssdk.core.sync.RequestBody.fromBytes(content.getBytes(StandardCharsets.UTF_8)));
            logger.log(Level.INFO, "Successfully uploaded report to S3: {0}", key);
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Error uploading report to S3: {0}", e.getMessage());
        }
    }

    private String getPipelineCode(Run<?, ?> run) {
        if (run instanceof org.jenkinsci.plugins.workflow.job.WorkflowRun) {
            org.jenkinsci.plugins.workflow.job.WorkflowRun workflowRun =
                    (org.jenkinsci.plugins.workflow.job.WorkflowRun) run;
            if (workflowRun.getParent().getDefinition()
                    instanceof org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition) {
                org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition definition =
                        (org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition)
                                workflowRun.getParent().getDefinition();
                return definition.getScript();
            } else {
                return "Pipeline definition not supported (e.g., loaded from SCM).";
            }
        }
        return "Pipeline code not available or job type not supported.";
    }

    private String getFreestyleSteps(Run<?, ?> run) {
        if (run.getParent() instanceof FreeStyleProject) {
            FreeStyleProject project = (FreeStyleProject) run.getParent();
            StringBuilder steps = new StringBuilder();
            project.getBuildersList().forEach(builder -> {
                steps.append("- ")
                        .append(builder.getDescriptor().getDisplayName())
                        .append("\n");
            });
            return steps.toString();
        }
        return "No steps available or not a Freestyle job.";
    }

    private long getBuildQueueTime(Run<?, ?> run) {
        long queueTime = 0;
        try {
            // Access the queue ID of the build
            long queueId = run.getQueueId();

            // Use Jenkins Queue API to get the queue item
            Queue.Item queueItem = Jenkins.get().getQueue().getItem(queueId);

            if (queueItem != null) {
                // Calculate the queue time: start time of the build - time in queue
                queueTime = (run.getStartTimeInMillis() - queueItem.getInQueueSince()) / 1000; // Convert to seconds
            }
        } catch (Exception e) {
            // Log or handle exceptions
            queueTime = -1; // Use -1 to indicate queue time couldn't be determined
        }
        return queueTime;
    }
}
