# Checks for puppet-agent and installs or updates if necessary
#
# @param nodes  Target nodeset for puppet-agent
# @param agent_version The minimum version of puppet-agent to install or update to
# @param update
#   Update existing puppet-agent versions
#
plan simp_bolt::install_puppet_agent (
  Boltlib::TargetSpec                  $nodes,
  Variant[SemVer,String]               $agent_version  = '5.5.14-1',
  Enum['repo','upload','repo+upload']  $method         = 'repo+upload',
  Boolean                              $strict_version = true,
  Boolean                              $permit_upgrade = false,
) {
  # Set up inventory facts and collect Red Hat nodes
  # ------------------------------------------------
  run_plan('facts', nodes => $nodes)
  $targets = get_targets($nodes).each |$target| { $target.set_var('agent_action_taken', 'none') }
  $rel_targets = $targets.filter |$target| { facts($target)['os']['family'] == 'RedHat' }

  # Check for currently installed puppet-agent package
  # --------------------------------------------------
  run_task('package::linux', $rel_targets,
    'Check for currently installed puppet-agent package',
    name   => 'puppet-agent',
    action => 'status'
  ).each |$result| {
    $result.target.set_var('agent_status', $result['status'])
    $result.target.set_var('agent_version', $result['version'])
  }


  # METHOD 'repo': Using OS package repositories
  # ============================================================================
  if $method in ['repo', 'repo+upload'] {

    # list puppet-agent releases
    # ----------------------------------------------------------
    $rel_targets.each |$target| {
      $r = $target.facts['os']['release']['major']
      $target.set_var('req_agent_version', "${agent_version}.${r}")
      run_command(
        "set -o pipefail; yum list available --showduplicates puppet-agent | \
          grep -w puppet-agent | awk '{print \$2}' | sort --version-sort",
        $target,
        'Find puppet-agent releases available from OS package repos',
        { '_catch_errors' =>  true }
      ).each |$result| {
        if $result.ok {
          $yum_list = $result.value['stdout'].split("\n")
          $target.set_var('yum_list', $yum_list )
          out::message($yum_list.join("\n* " ))
          if $agent_version.type == 'String' {

        } else {
          $target.set_var('yum_list', false)
        }
      }
    }


    # Installing a fresh puppet-agent

    $rel_targets.filter |$target| {
      $target.vars['agent_status'] == 'uninstalled' and $strict_cmp
    }.each |$target| {
      $result = run_task('package::linux', $target,
        'Install puppet-agent ${agent_version} from OS package repo',
        name    => 'puppet-agent',
        version =>  $target.vars['req_agent_version'],
        action  => 'install'
      )
      $target.set_var('agent_action_taken', "install puppet-agent ${target.vars['req_agent_version']} from OS package repo'")
      $target.set_var('agent_action_result', $result)
    }

    # Only update if agent is installed, but older than the version we want
    $upgrade_targets  = $targets.filter |$target| {
      $target.vars['agent_status'] == 'installed'
        and versioncmp($target.vars['agent_version'], $agent_version) == -1
    }






  $results = $targets.map |$target| {
    $target.vars.filter |$k,$v| { $k in ['agent_action_taken', 'yum_list']  } + $target.facts.filter |$k, $v| { $k in ['os'] }
  }
  return( $results )

  ###  $el_releases = ['6','7']
  ###  $el_releases.each |$r| {
  ###    $rel_targets = ($install_targets + $upgrade_targets).filter |$target| {
  ###      facts($target)['os']['family'] == 'RedHat' and facts($target)['os']['release']['major'] == $r
  ###    }
  ###    $install_rel_targets = $rel_targets.filter |$target| { $target in $install_targets }
  ###    $upgrade_rel_targets = $rel_targets.filter |$target| { $target in $upgrade_targets }
  ###
  ###    run_task('simp_bolt::payum', $rel_targets,
  ###      'Examine what puppet-agent releases are available via OS package repo',
  ###      version => "${agent_version}.el${r}"
  ###    ).each |$result| {
  ###      $result.target.set_var('repo_puppet_version', $result['_output'])
  ###    }
  ###
  ###    # Install $agent_version from yum if it's available
  ###    $yum_fresh_install_rel_targets = $install_rel_targets.filter |$target| {
  ###      versioncmp($target.vars['repo_puppet_version'], "${agent_version}.el${r}") == 0
  ###    }
  ###    run_task('package::linux', $yum_fresh_install_rel_targets,
  ###      "Install puppet-agent '${agent_version}.el${r}' from OS package repo",
  ###      name    => 'puppet-agent',
  ###      version => "${agent_version}.el${r}",
  ###      action  => 'install'
  ###    )
  ###
  ###    # NOTE: Is it really okay to just install any newer version if the one we wanted wasn't available?
  ###    $yum_newer_install_rel_targets = $install_rel_targets.filter |$target| {
  ###      versioncmp($target.vars['repo_puppet_version'], "${agent_version}.el${r}") == 1
  ###    }
  ###    run_task('package::linux', $yum_newer_install_rel_targets,
  ###      "Install (latest available) puppet-agent from OS repo",
  ###      name    => 'puppet-agent',
  ###      action  => 'install'
  ###    )
  ###
    ###     # Copy rpm file to target and install if yum does not offer a suitable version
    ###     # NOTE: as long as this plan has the capability to upload and install RPMs,
    ###     #       there should be an option to just do that and ignore the node's yum repos
    ###     #       altogether.
    ###     $rpm_upload_targets = $repo_puppet_version.filter |$result| {
    ###       versioncmp($result[_output], "${agent_version}.el${r}") == -1
    ###     }.map |$result| { $result.target }
    ###
    ###     # No need to check for rpm if yum is sufficient
    ###     if !empty($rpm_upload_targets) {
    ###       $local_agent_rpm = "simp_bolt/puppet-agent-${agent_version}.el${r}.x86_64.rpm"
    ###       $rpm_upload_target_list = $rpm_upload_targets.map |$target| { $target.name }.join(', ')
    ###       if find_file($local_agent_rpm) {
    ###         notice("uploading puppet-agent package from '$local_agent_rpm' to ${rpm_upload_target_list}")
    ###         upload_file(
    ###           "simp_bolt/puppet-agent-${agent_version}.el${r}.x86_64.rpm",
    ###           "/var/local/puppet-agent-${agent_version}.el${r}.x86_64.rpm",
    ###           $rpm_upload_targets
    ###         )
    ###         run_command(
    ###           "yum localinstall -y /var/local/puppet-agent-${agent_version}.el${r}.x86_64.rpm",
    ###           $rpm_upload_targets
    ###         )
    ###       } else {
    ###         warning("File at '${local_agent_rpm}' unavailable for upload to ${rpm_upload_target_list}")
    ###       }
    ###     }
    ###
    ### ###    # For updates
    ### ###    $update_rel_subset = $upgrade_targets.filter |$target| { $target.vars['os_major_version'] == $r }
    ### ###    ### $rel_updates = $ver_upd_results.filter |$result| { $result['os']['release']['major'] == $r }
    ### ###    ### $update_rel_subset = $rel_updates.map |$result| { $result.target }
    ### ###    if !empty($update_rel_subset) {
    ### ###      if $permit_upgrade {
    ### ###        # Check existing repo for adequate version
    ### ###        $urepo_version = run_task('simp_bolt::payum',
    ### ###          $update_rel_subset,
    ### ###          version => "${agent_version}.el${r}"
    ### ###        )
    ### ###        # Install agent_version if available from yum
    ### ###        $yum_update_subset = $urepo_version.filter |$result| { versioncmp($result[_output], "${agent_version}.el${r}") == 0 }
    ### ###        $update_target_subset = $yum_update_subset.map |$result| { $result.target }
    ### ###        run_task( 'package::linux',
    ### ###          $update_target_subset,
    ### ###          name    => 'puppet-agent',
    ### ###          version => "${agent_version}.el${r}",
    ### ###          action  => 'upgrade')
    ### ###        # Install newer agent_version if available from yum
    ### ###        $yum_newer_subset = $urepo_version.filter |$result| { versioncmp($result[_output], "${agent_version}.el${r}") == 1 }
    ### ###        $update_newer_subset = $yum_newer_subset.map |$result| { $result.target }
    ### ###        run_task( 'package::linux',
    ### ###          $update_newer_subset,
    ### ###          name    => 'puppet-agent',
    ### ###          action  => 'upgrade'
    ### ###        )
    ### ###        # Copy rpm file to target and install
    ### ###        $yum_no_subset = $urepo_version.filter |$result| { versioncmp($result[_output], "${agent_version}.el${r}") == -1 }
    ### ###        $rpm_update_subset = $yum_no_subset.map |$result| { $result.target }
    ### ###        # No need to check for rpm if yum is sufficient
    ### ###        if !empty($rpm_update_subset) {
    ### ###          if file::exists("simp_bolt/puppet-agent-${agent_version}.el${r}.x86_64.rpm") {
    ### ###            upload_file("simp_bolt/puppet-agent-${agent_version}.el${r}.x86_64.rpm", "/var/local/puppet-agent-${agent_version}.el${r}.x86_64.rpm", $rpm_update_subset)
    ### ###            run_command("yum localinstall -y /var/local/puppet-agent-${agent_version}.el${r}.x86_64.rpm", $rpm_update_subset)
    ### ###          } else {
    ### ###            warning("no puppet-agent is available for update on ${rpm_update_subset.map |$target| { $target.name }.join(', ')}")
    ### ###          }
    ### ###        }
    ### ###      } else {
    ### ###        warning("${update_subset} require updates but the update parameter is false")
    ### ###      }
    ### ###    }
}