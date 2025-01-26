package io.jenkins.plugins.globale;

import hudson.Extension;
import java.util.ArrayList;
import java.util.List;
import jenkins.model.GlobalConfiguration;
import org.kohsuke.stapler.DataBoundConstructor;
import org.kohsuke.stapler.DataBoundSetter;

@Extension
public class JenkinsBuildFailureReporterConfig extends GlobalConfiguration {

    private List<String> includedProjects; // List of projects to include

    @DataBoundConstructor
    public JenkinsBuildFailureReporterConfig() {
        load(); // Load the saved configuration
        if (includedProjects == null) {
            includedProjects = new ArrayList<>(); // Initialize if null
        }
    }

    public List<String> getIncludedProjects() {
        return includedProjects;
    }

    @DataBoundSetter
    public void setIncludedProjects(List<String> includedProjects) {
        this.includedProjects = includedProjects;
        save(); // Save configuration whenever it's updated
    }

    /**
     * Check if a project is included in the configuration.
     *
     * @param projectName the name of the project
     * @return true if the project is included, false otherwise
     */
    public boolean isProjectIncluded(String projectName) {
        return includedProjects.contains(projectName);
    }
}
