# Selected Perl snippets for examination and/or discussion
# vim:ts=4

###
### Platform dependencies, trying to get a package to run in three environments
###

# set up vars based on parameters, platform, environment
#
# "ora_" for production 9i, 10g, etc. (all except XE)
$ORAPROCSTR = "ora_";
if ( "XE" eq "$ORACLE_SID" ) {
    $ORAPROCSTR = "xe_";
    $cohconnstr = $ORACLE_SID;
} elsif ( $OSIS =~ /windows/ ) {    # Windows Server 2003, Oracle Agile 9
    $cohconnstr = "";
} elsif ( $OSIS =~ /Linux/ ) {      #
    $cohconnstr = "--connect \(DESCRIPTION=\(ADDRESS=\(PROTOCOL=BEQ\)\(PROGRAM=oracle\)\(ARGV0=oracle$ORACLE_SID\)\(ARGS=\"\(DESCRIPTION=\(LOCAL=YES\)\(ADDRESS=\(PROTOCOL=BEQ\)\)\)\"\)\(ENVS=\"ORACLE_SID=$ORACLE_SID,ORACLE_HOME=$ORACLE_HOME\"\)\)\)";
} else {                            # HP-UX, old sh shell
    $cohconnstr = "--connect \\(DESCRIPTION=\\(ADDRESS=\\(PROTOCOL=BEQ\\)\\(PROGRAM=oracle\\)\\(ARGV0=oracle$ORACLE_SID\\)\\(ARGS=\"\\(DESCRIPTION=\\(LOCAL=YES\\)\\(ADDRESS=\\(PROTOCOL=BEQ\\)\\)\\)\"\\)\\(ENVS=\"ORACLE_SID=$ORACLE_SID,ORACLE_HOME=$ORACLE_HOME\"\\)\\)\\)";
}

###
### Non-DRY code, etc.
###

elsif ( $cmd =~ /^blocklocks/ ) {

    $usestr = "blocklocks -w count -c count [ -a age_in_seconds ]";
    param_crit_ge_warn();

    # default to 120 seconds
    if ( not($AGE) ) {
        $AGE = 120;
    }

    # SQL
    #    --name="SELECT ltrim(to_char(count(*)))FROM sys.v_\$lock WHERE request not in (0,2) AND ctime > ${AGE}"
    #    --name="SELECT ltrim(to_char(count(*)))FROM sys.v_$lock WHERE request not in (0,2) AND ctime > ${AGE}"

    $cohstr = "--name2=BlockingLocks --mode sql --name=SELECT%20ltrim%28to%5Fchar%28count%28%2A%29%29%29FROM%20sys%2Ev%5F%24lock%20WHERE%20request%20not%20in%20%280%2C2%29%20AND%20ctime%20%3E%20$AGE";
    runcohstr($cohstr);

}

###
### "Here docs"; use of Oracle:DBI; comparing to result from last run for a delta; formatting for Nagios plugin results
###

elsif ( $cmd =~ /^redologgenrate/ ) {

    $usestr = "redologgenrate -w deltacount -c deltacount";
    param_crit_ge_warn();

    # get a database handle
    $dbh = DBI->connect( 'dbi:Oracle:', '/', '' );

    # SQL for this query
    $sqlstr = <<'END_SQL';
SELECT value
FROM sys.v_$sysstat
WHERE name = 'redo size'
END_SQL

    # get a statement handle
    $sth =
      $dbh->prepare( $sqlstr, { pagesize => 0, head => "off", echo => "off", space => 0, newpage => 0, line => 500 } );

    # execute the statement handle
    $sth->execute();

    # loop through the results
    while ( my ($line) = $sth->fetchrow() ) {
        $result = "$line";
    }

    die "Redo log query failed to return a result\n" unless ($result);
    chk_ora_err($result);

    # clean up
    $sth->finish();
    $dbh->disconnect();

    chomp($result);
    $result = trim($result);

    if ( $debug >= 1 ) { print "Result:\n.$result.\n" }

    $NOW = $result;

    historysetup();
    $HISTOFIL = "$historydir/redologgenrate_$ORACLE_SID.log";

    if ( -f $HISTOFIL ) {
        open( HISTOFH, "$HISTOFIL" )
          || die "Could not open $HISTOFIL for read";
        $THEN = <HISTOFH>;
        close(HISTOFH);
        $THEN = trim($THEN);
    } else {
        $THEN = $NOW;
    }

    if ( $debug >= 1 ) { print Data::Dumper->Dump( [ $result, $NOW, $THEN ], [qw(result NOW THEN)] ) . "\n"; }

    # clobber any old one
    writeHistoryFile( $HISTOFIL, "$NOW" );

    $DIFF = $NOW - $THEN;
    if ( $DIFF < 0 ) {
        $DELTA = $NOW;
    } else {
        $DELTA = $DIFF;
    }
    if ( $debug >= 1 ) { print "Delta:\n$DELTA\n" }

    rtn_trigger_if_high_1x1( $DELTA, "RedoLogCntIncr", "", "", "" );
}

