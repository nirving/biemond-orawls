# == Define: orawls::extenddomain
#
# extend an existing weblogic domain
##
define orawls::extenddomain (
  $version                               = hiera('wls_version', 1111),  # 1036|1111|1211|1212|1213
  $weblogic_home_dir                     = hiera('wls_weblogic_home_dir'), # /opt/oracle/middleware11gR1/wlserver_103
  $wls_domains_dir                       = hiera('wls_domains_dir'               , undef),
  $middleware_home_dir                   = hiera('wls_middleware_home_dir'), # /opt/oracle/middleware11gR1
  $domain_name                           = hiera('domain_name'),
  $jdk_home_dir                          = hiera('wls_jdk_home_dir'), # /usr/java/jdk1.7.0_45
  $log_output                            = true, # true|false
  $download_dir                          = hiera('wls_download_dir'), # /data/install
  $domain_template                       = hiera('domain_template'               , 'oam'),
  $java_arguments                        = hiera('domain_java_arguments'         , {}),
  $repository_database_url               = hiera('repository_database_url'       , undef), #jdbc:oracle:thin:@192.168.50.5:1521:XE
  $rcu_database_url                      = hiera('rcu_database_url'       , undef), #jdbc:oracle:thin:@192.168.50.5:1521:XE
  $repository_prefix                     = hiera('repository_prefix'             , 'DEV'),
  $repository_password                   = hiera('repository_password'           , 'Welcome01'),
  $repository_sys_password               = hiera('repository_sys_password'       , 'Welcome01'),
  $weblogic_user                         = hiera('wls_weblogic_user'             , 'weblogic'),
  $weblogic_password                     = hiera('domain_wls_password'),
  $os_user                               = hiera('wls_os_user'), # oracle
  $os_group                              = hiera('wls_os_group'), # dba
  $adminserver_address                   = hiera('domain_adminserver_address'    , undef),


)

{
  if ( $wls_domains_dir == undef ) {
    $domains_dir = "${middleware_home_dir}/user_projects/domains"
  } else {
    $domains_dir = $wls_domains_dir
  }

  $domain_dir = "${domains_dir}/${domain_name}"

  # check if the domain already exists
  $found = domain_exists($domain_dir)
  if $found == undef {
    $continue = true
  } else {
    if ($found) {
      $continue = true
    } else {
      notify { "orawls::extend_domain ${title} ${domain_dir} ${version} does not exists": }
      $continue = false
    }
  }
  if ($continue) {
    notify { "orawls::extend_domain ${domain_dir} exists": }
    if $version == 1112 {
      $templateOAM       = "${middleware_home_dir}/Oracle_IDM1/common/templates/applications/oracle.oam_ds_11.1.2.0.0_template.jar"
    }
    if $domain_template == 'oam' {
      $templateFile  = 'orawls/domains/extend_domain_oam.py.erb'
      $wlstPath      = "${middleware_home_dir}/Oracle_IDM1/common/bin"
    }

    $exec_path        = "${jdk_home_dir}/bin:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin"

    Exec {
      logoutput => $log_output,
    }

    if $log_dir == undef {
      $oam_nodemanager_log_dir   = "${domain_dir}/servers/oam_server1/logs"
    } else {
      $oam_nodemanager_log_dir   = $log_dir

      # create all log folders
      if !defined(Exec["create ${log_dir} directory"]) {
        exec { "create ${log_dir} directory":
          command => "mkdir -p ${log_dir}",
          unless  => "test -d ${log_dir}",
          user    => 'root',
          path    => $exec_path,
        }
      }

      if !defined(File[$log_dir]) {
        file { $log_dir:
          ensure  => directory,
          recurse => false,
          replace => false,
          require => Exec["create ${log_dir} directory"],
          mode    => '0775',
          owner   => $os_user,
          group   => $os_group,
        }
      }
    }

    if !defined(File[$download_dir]) {
      file { $download_dir:
          ensure  => directory,
          mode    => '0775',
          owner   => $os_user,
          group   => $os_group,
      }
    }

    # the domain.py used by the wlst
    file { "extenddomain.py ${domain_name} ${title}":
      ensure  => present,
      path    => "${download_dir}/extend_domain_${domain_name}.py",
      content => template($templateFile),
      replace => true,
      backup  => false,
      mode    => '0775',
      owner   => $os_user,
      group   => $os_group,
      require => File[$download_dir],
    }
    if !defined(File[$domains_dir]) {
      # check oracle install folder
      file { $domains_dir:
        ensure  => directory,
        recurse => false,
        replace => false,
        mode    => '0775',
        owner   => $os_user,
        group   => $os_group,
      }
    }

    # extend domain
    exec { "execwlst ${domain_name} ${title}":
      command     => "${wlstPath}/wlst.sh ${download_dir}/extend_domain_${domain_name}.py",
      environment => ["JAVA_HOME=${jdk_home_dir}"],
  
      require     => [File["extenddomain.py ${domain_name} ${title}"],
                      File[$domains_dir]],
      timeout     => 0,
      path        => $exec_path,
      user        => $os_user,
      group       => $os_group,
    }

    yaml_setting { "domain ${title}":
      target =>  '/etc/wls_domains.yaml',
      key    =>  "domains/${domain_name}",
      value  =>  $domain_dir,
    }

    if ($domain_template == 'oam') {

      file { "${download_dir}/${title}psa_opss_upgrade.rsp":
        ensure  => present,
        content => template('orawls/oim/psa_opss_upgrade.rsp.erb'),
        mode    => '0775',
        owner   => $os_user,
        group   => $os_group,
        backup  => false,
      }

      exec { "exec PSA OPSS store upgrade ${domain_name} ${title}":
        command     => "${middleware_home_dir}/oracle_common/bin/psa -response ${download_dir}/${title}psa_opss_upgrade.rsp",
        require     => [Exec["execwlst ${domain_name} ${title}"],File["${download_dir}/${title}psa_opss_upgrade.rsp"],],
        timeout     => 0,
        path        => $exec_path,
        user        => $os_user,
        group       => $os_group,
      }

      exec { "execwlst create OPSS store ${domain_name} ${title}":
        command     => "${wlstPath}/wlst.sh ${middleware_home_dir}/Oracle_IDM1/common/tools/configureSecurityStore.py -d ${domain_dir} -m create -c IAM -p ${repository_password}",
        environment => ["JAVA_HOME=${jdk_home_dir}"],
        require     => [Exec["execwlst ${domain_name} ${title}"],Exec["exec PSA OPSS store upgrade ${domain_name} ${title}"],],
        timeout     => 0,
        path        => $exec_path,
        user        => $os_user,
        group       => $os_group,
      }

      exec { "execwlst validate OPSS store ${domain_name} ${title}":
        command     => "${wlstPath}/wlst.sh ${middleware_home_dir}/Oracle_IDM1/common/tools/configureSecurityStore.py -d ${domain_dir} -m validate",
        environment => ["JAVA_HOME=${jdk_home_dir}"],
        require     => [Exec["execwlst ${domain_name} ${title}"],
                        Exec["execwlst create OPSS store ${domain_name} ${title}"]],
        timeout     => 0,
        path        => $exec_path,
        user        => $os_user,
        group       => $os_group,
      }
    }

    exec { "extenddomain.py ${domain_name} ${title}":
      command => "rm ${download_dir}/extend_domain_${domain_name}.py",
      require => Exec["execwlst ${domain_name} ${title}"],
      path    => $exec_path,
      user    => $os_user,
      group   => $os_group,
    }
  }
}
