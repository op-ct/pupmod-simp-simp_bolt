# Installs or updates `puppet-agent` to a specified version on EL targets.
#   Can upload package files if repos are not available.
#
# On offline systems (or systems
#
# Features:
#
# * Works with or without access to internet/package repositories
# * Supports SemVerRange syntax for packages installed from OS repositories
# * Does not upgrade existing packages without explicit permission
#   (use parameter `permit_upgrade=true`)
# * Does not install new OS package repositories to provide `puppet-agent`
# * Does not rely on 'puppet-agent' feature
#
# Limitations:
#
# * Only EL OS targets are currently supported
# * Does not install new OS package repositories to provide `puppet-agent`
#
# @example
#
#   bolt plan run simp_bolt::install_puppet_agent \
#      -n target1,target2,target3 --run-as-root \
#      version='5.5.17-1'
#
# @example
#
#   bolt plan run simp_bolt::install_puppet_agent \
#      -n target1,target2,target3 --run-as-root \
#      version='~> 5.2.0'
#
# @example
#
#   bolt plan run simp_bolt::install_puppet_agent \
#      -n target1,target2,target3 --run-as-root \
#      version='5.2.0 || >= 5.5 < 7.0'
#
# @param nodes  Target nodeset for puppet-agent
# @param version
#   The version of the puppet-agent package to install, or a SemVerRange
#   of acceptable versions.
#
#   * Explicit version numbers may include release number and moniker,
#     e.g., `5.5.17-1` or `5.5.17-1.el8`.
#
#   For SemVerRange grammar, see: https://github.com/npm/node-semver#ranges
#
# @param install_method
#   Method used to
#
# @param permit_upgrade
#   By default, an existing `puppet-agent` packages are not upgraded.
#
# @param upload_dirs
#   TODO
#
# - [ ] TODO upload files
# - [ ] TODO code refactor / reuse
# - [ ] TODO sane reporting
# - [ ] TODO support 'latest' and 'installed' in $version
plan simp_bolt::install_puppet_agent (
  Boltlib::TargetSpec                  $nodes,
  String                               $version        = '5.5.14-1',
  Enum['repo','upload','repo+upload']  $install_method = 'repo+upload',
  Boolean                              $strict_version = true,
  Boolean                              $permit_upgrade = false,
  Array[String]                        $upload_dirs    = [
    'simp_pupmod/files',
    'simp_pupmod/../../../files',
  ]
) {
  $version_range = SemVerRange($version)

  # Set up inventory facts and collect Red Hat nodes
  # ------------------------------------------------
  run_plan('facts', nodes             => $nodes)
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
    unless empty($result['version']) {
      $result.target.set_var('orig_agent_version', $result['version'])
    }
  }


  # METHOD 'repo': Using OS package repositories
  # ============================================================================
  if $install_method in ['repo', 'repo+upload'] {
    out::message( '==== YUM REPO RPM section' )

    # find matching puppet-agent release in OS package repos
    # ----------------------------------------------------------
    # Query OS package repos for available `puppet-agent` versions and select
    # the best match for $version, trying in this order:
    #
    #   1. if there is a perfect match for $version, take it!
    #   2. Otherwise, use $version as a SemVerRange and select the latest
    #      matching package version
    #   3. Otherwise, record that a suitable package wasn't available
    #
    run_command(
      "set -o pipefail; yum list available --showduplicates puppet-agent \
          | grep -w puppet-agent | awk '{print \$2}' | sort --version-sort",
      $rel_targets,
      'Find puppet-agent releases available from OS package repos',
      { '_catch_errors' =>  true }
    ).each |$result| {
      $target = $result.target

      if $result.ok {
        $yum_list = $result.value['stdout'].split("\n")
        debug("+++ yum_list:\n* ${$yum_list.join("\n* " )}")

        $pkg_agent_version = "${version}.el${facts($target)['os']['release']['major']}"
        if ($pkg_agent_version in $yum_list) {
          out::message(
            "=== ${target.name}: Found EXACT match for puppet-agent \
            ${pkg_agent_version} in OS repos".regsubst(/ {2,}/,'')
          )

          $target.set_var('agent_repo_pkgver', $pkg_agent_version)
        } elsif ($version in $yum_list) {
          out::message("=== ${target.name}: Found EXACT match for puppet-agent ${version} in OS repos")
          $target.set_var('agent_repo_pkgver', $version)
        } else {
          $version_range = SemVerRange.new($version)
          $target.set_var('agent_repo_pkgver', false)

          $yum_list.reverse_each |$repo_pkg_version| {
            $repo_pkg_semver = $repo_pkg_version.regsubst(/-\d+(\.[a-z0-9_-]*)?$/,'')
            if $repo_pkg_semver =~ $version_range {
              out::message(
                "=== ${target.name}: SemVerRange '${agent_version_range}' \
                matched puppet-agent '${repo_pkg_version}' in OS repo".regsubst(/ {2,}/,'')
              )
              $target.set_var('agent_repo_pkgver', $repo_pkg_version)
              break()
            }
          }
          unless $target.vars['agent_repo_pkgver'] {
            out::message( @("MSG"/L)
              === ${target.name}: OS repos didn't provide \
                a match for puppet-agent version '${agent_version_range}'"
              | MSG
            )
          }
        }

      } else {
          out::message("=== ${target.name}: OS repos didn't provide any version of puppet-agent")
        $target.set_var('agent_repo_pkgver', false)
      }
    }

    # Installing a fresh puppet-agent

    out::message( '==== YUM REPO Installing a fresh agent' )
    $rel_targets.filter |$target| {
      $target.vars['agent_status'] == 'uninstalled' and $target.vars['agent_repo_pkgver']
    }.each |$target| {
      $result = catch_errors(['bolt/run-failure']) || {
        run_task('package::linux', $target,
          "Install puppet-agent '${target.vars['agent_repo_pkgver']}' from OS package repo",
          name          => 'puppet-agent',
          version       => $target.vars['agent_repo_pkgver'],
          action        => 'install',
          _run_as       => 'root',
          _catch_errors => true,
        )
      }
      $target.set_var(
        'agent_action_taken',
        "install puppet-agent '${target.vars['agent_repo_pkgver']}' from OS package repo"
      )
      out::message(String($result))
      $target.set_var('agent_action_result', $result.to_data)
    }

    # TODO upgrade
    # TODO reuse package install code?
    # Only update if agent is installed, but older than the version we want
    $upgrade_targets  = $targets.filter |$target| {
      $target.vars['agent_status'] == 'installed'
        and versioncmp($target.vars['orig_agent_version'], $version) == -1
    }
  }

  if $install_method in ['upload', 'repo+upload'] {
    out::message( '==== UPLOAD RPM section' )
  }


  out::message( '==== COMPILE RESULTS section' )
  $results = {
    'orig_agent_version' => $version,
    'install_method'        => $install_method,
    'targets'       => Hash($targets.map |$target| {
      [$target.name, $target.vars]
      ###+ $target.facts.filter |$k, $v| { $k in ['os'] }
    })
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
  ###      version                    => "${version}.el${r}"
  ###    ).each |$result| {
  ###      $result.target.set_var('repo_puppet_version', $result['_output'])
  ###    }
  ###
  ###    # Install $version from yum if it's available
  ###    $yum_fresh_install_rel_targets = $install_rel_targets.filter |$target| {
  ###      versioncmp($target.vars['repo_puppet_version'], "${version}.el${r}") == 0
  ###    }
  ###    run_task('package::linux', $yum_fresh_install_rel_targets,
  ###      "Install puppet-agent '${version}.el${r}' from OS package repo",
  ###      name                       => 'puppet-agent',
  ###      version                    => "${version}.el${r}",
  ###      action                     => 'install'
  ###    )
  ###
  ###    # NOTE: Is it really okay to just install any newer version if the one we wanted wasn't available?
  ###    $yum_newer_install_rel_targets = $install_rel_targets.filter |$target| {
  ###      versioncmp($target.vars['repo_puppet_version'], "${version}.el${r}") == 1
  ###    }
  ###    run_task('package::linux', $yum_newer_install_rel_targets,
  ###      "Install (latest available) puppet-agent from OS repo",
  ###      name                       => 'puppet-agent',
  ###      action                     => 'install'
  ###    )
  ###
    ###     # Copy rpm file to target and install if yum does not offer a suitable version
    ###     # NOTE: as long as this plan has the capability to upload and install RPMs,
    ###     #       there should be an option to just do that and ignore the node's yum repos
    ###     #       altogether.
    ###     $rpm_upload_targets = $repo_puppet_version.filter |$result| {
    ###       versioncmp($result[_output], "${version}.el${r}") == -1
    ###     }.map |$result| { $result.target }
    ###
    ###     # No need to check for rpm if yum is sufficient
    ###     if !empty($rpm_upload_targets) {
    ###       $local_agent_rpm = "simp_bolt/puppet-agent-${version}.el${r}.x86_64.rpm"
    ###       $rpm_upload_target_list = $rpm_upload_targets.map |$target| { $target.name }.join(', ')
    ###       if find_file($local_agent_rpm) {
    ###         notice("uploading puppet-agent package from '$local_agent_rpm' to ${rpm_upload_target_list}")
    ###         upload_file(
    ###           "simp_bolt/puppet-agent-${version}.el${r}.x86_64.rpm",
    ###           "/var/local/puppet-agent-${version}.el${r}.x86_64.rpm",
    ###           $rpm_upload_targets
    ###         )
    ###         run_command(
    ###           "yum localinstall -y /var/local/puppet-agent-${version}.el${r}.x86_64.rpm",
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
    ### ###          version => "${version}.el${r}"
    ### ###        )
    ### ###        # Install orig_agent_version if available from yum
    ### ###        $yum_update_subset = $urepo_version.filter |$result| { versioncmp($result[_output], "${version}.el${r}") == 0 }
    ### ###        $update_target_subset = $yum_update_subset.map |$result| { $result.target }
    ### ###        run_task( 'package::linux',
    ### ###          $update_target_subset,
    ### ###          name    => 'puppet-agent',
    ### ###          version => "${version}.el${r}",
    ### ###          action  => 'upgrade')
    ### ###        # Install newer orig_agent_version if available from yum
    ### ###        $yum_newer_subset = $urepo_version.filter |$result| { versioncmp($result[_output], "${version}.el${r}") == 1 }
    ### ###        $update_newer_subset = $yum_newer_subset.map |$result| { $result.target }
    ### ###        run_task( 'package::linux',
    ### ###          $update_newer_subset,
    ### ###          name    => 'puppet-agent',
    ### ###          action  => 'upgrade'
    ### ###        )
    ### ###        # Copy rpm file to target and install
    ### ###        $yum_no_subset = $urepo_version.filter |$result| { versioncmp($result[_output], "${version}.el${r}") == -1 }
    ### ###        $rpm_update_subset = $yum_no_subset.map |$result| { $result.target }
    ### ###        # No need to check for rpm if yum is sufficient
    ### ###        if !empty($rpm_update_subset) {
    ### ###          if file::exists("simp_bolt/puppet-agent-${version}.el${r}.x86_64.rpm") {
    ### ###            upload_file("simp_bolt/puppet-agent-${version}.el${r}.x86_64.rpm", "/var/local/puppet-agent-${version}.el${r}.x86_64.rpm", $rpm_update_subset)
    ### ###            run_command("yum localinstall -y /var/local/puppet-agent-${version}.el${r}.x86_64.rpm", $rpm_update_subset)
    ### ###          } else {
    ### ###            warning("no puppet-agent is available for update on ${rpm_update_subset.map |$target| { $target.name }.join(', ')}")
    ### ###          }
    ### ###        }
    ### ###      } else {
    ### ###        warning("${update_subset} require updates but the update parameter is false")
    ### ###      }
    ### ###    }
}
