#!/usr/bin/env perl

use strict;
use warnings;

use Test::MockTime qw( :all );
use Test::Most;

use DDG::Test::Location;

subtest 'NumberStyler' => sub {

    { package NumberRoleTester; use Moo; with 'DDG::GoodieRole::NumberStyler'; 1; }

    subtest 'Initialization' => sub {
        new_ok('NumberRoleTester', [], 'Applied to a class');
        isa_ok(NumberRoleTester::number_style_regex(), 'Regexp', 'number_style_regex()');
    };

    subtest 'Valid numbers' => sub {

        my @valid_test_cases = (
            [['0,013'] => 'euro'],
            [['4,431',      '4.321'] => 'perl'],
            [['4,431',      '4,32']  => 'euro'],
            [['4534,345.0', '1']     => 'perl'],    # Unenforced commas.
            [['4,431',     '4,32', '5,42']       => 'euro'],
            [['4,431',     '4.32', '5.42']       => 'perl'],
            [['4_431_123', '4 32', '99.999 999'] => 'perl'],
        );

        foreach my $tc (@valid_test_cases) {
            my @numbers           = @{$tc->[0]};
            my $expected_style_id = $tc->[1];
            is(NumberRoleTester::number_style_for(@numbers)->id,
                $expected_style_id, '"' . join(' ', @numbers) . '" yields a style of ' . $expected_style_id);
        }
    };

    subtest 'Invalid numbers' => sub {
        my @invalid_test_cases = (
            [['5234534.34.54', '1'] => 'has a mal-formed number'],
            [['4,431',     '4,32',     '4.32']       => 'is confusingly ambiguous'],
            [['4,431',     '4.32.10',  '5.42']       => 'is hard to figure'],
            [['4,431',     '4,32,100', '5.42']       => 'has a mal-formed number'],
            [['4,431',     '4,32,100', '5,42']       => 'is too crazy to work out'],
            [['4_431_123', "4\t32",    '99.999 999'] => 'no tabs in numbers'],
        );

        foreach my $tc (@invalid_test_cases) {
            my @numbers = @{$tc->[0]};
            my $why_not = $tc->[1];
            is(NumberRoleTester::number_style_for(@numbers), undef, '"' . join(' ', @numbers) . '" fails because it ' . $why_not);
        }
    };

};

subtest 'Dates' => sub {

    { package DatesRoleTester; use Moo; with 'DDG::GoodieRole::Dates'; 1; }

    my $test_datestring_regex;
    my $test_formatted_datestring_regex;
    my $test_descriptive_datestring_regex;

    subtest 'Initialization' => sub {
        new_ok('DatesRoleTester', [], 'Applied to a class');
        $test_datestring_regex = DatesRoleTester::datestring_regex();
        isa_ok($test_datestring_regex, 'Regexp', 'datestring_regex()');
        $test_formatted_datestring_regex = DatesRoleTester::formatted_datestring_regex();
        isa_ok($test_formatted_datestring_regex, 'Regexp', 'formatted_datestring_regex()');
        $test_descriptive_datestring_regex = DatesRoleTester::descriptive_datestring_regex();
        isa_ok($test_descriptive_datestring_regex, 'Regexp', 'descriptive_datestring_regex()');
    };

    subtest 'Working single dates' => sub {
        my %dates_to_match = (
            # Defined formats:
            #ISO8601
            '2014-11-27'                => 1417046400,
            '1994-02-03 14:15:29 -0100' => 760288529,
            '1994-02-03 14:15:29'       => 760284929,
            '1994-02-03T14:15:29'       => 760284929,
            '19940203T141529Z'          => 760284929,
            '19940203'                  => 760233600,
            #HTTP
            'Sat, 09 Aug 2014 18:20:00' => 1407608400,
            # RFC850
            '08-Feb-94 14:15:29 GMT' => 760716929,
            # date(1) default
            'Sun Sep  7 15:57:56 EST 2014' => 1410123476,
            'Sun Sep  7 15:57:56 EDT 2014' => 1410119876,
            'Sun Sep 14 15:57:56 UTC 2014' => 1410710276,
            'Sun Sep 7 20:11:44 CET 2014'  => 1410117104,
            'Sun Sep 7 20:11:44 BST 2014'  => 1410117104,
            # RFC 2822
            'Sat, 13 Mar 2010 11:29:05 -0800' => 1268508545,
            # HTTP (without day) - any TZ
            # %d %b %Y %H:%M:%S %Z
            '01 Jan 2012 00:01:20 UTC' => 1325376080,
            '22 Jun 1998 00:00:02 GMT' => 898473602,
            '07 Sep 2014 20:11:44 CET' => 1410117104,
            '07 Sep 2014 20:11:44 cet' => 1410117104,
            '09 Aug 2014 18:20:00'     => 1407608400,
            #Undefined/Natural formats:
            '13/12/2011'        => 1323734400,     #DMY
            '01/01/2001'        => 978307200,      #Ambiguous, but valid
            '29 June 2014'      => 1404000000,     #DMY
            '05 Mar 1990'       => 636595200,      #DMY (short)
            'June 01 2012'      => 1338508800,     #MDY
            'May 05 2011'       => 1304553600,     #MDY
            'may 01 2010'       => 1272672000,
            '1st june 1994'     => 770428800,
            '5 th january 1993' => 726192000,
            'JULY 4TH 1976'     => 205286400,
            '07/13/1984'        => 458524800,
            '7/13/1984'         => 458524800,
            '13/07/1984'        => 458524800,
            '13.07.1984'        => 458524800,
            '7.13.1984'         => 458524800,
            'june-01-2012'      => 1338508800,
            'feb/01/2010'       => 1264982400,
            '01-jun-2012'       => 1338508800,
            '01/june/2012'      => 1338508800,
            'JUN-1-2012'        => 1338508800,
            '4-jUL-1976'        => 205286400,
            '2001-1-1'          => 978307200,
            'jan 6, 2014'       => 1388966400,
            '6, jan 2014'       => 1388966400,
            '6 jan, 2014'       => 1388966400,
            '29 feb, 2012'      => 1330473600,
            '2038-01-20'        => 2147558400,     # 32-bit signed int UNIX epoch ends 2038-01-19
            '1780-01-20'        => -5994172800,    # Way before 32-bit signed int epoch
        );

        foreach my $test_date (sort keys %dates_to_match) {
            like($test_date, qr/^$test_datestring_regex$/, "$test_date matches the datestring_regex");
            like($test_date, qr/^$test_formatted_datestring_regex$/, "$test_date matches the formatted_datestring_regex");

            # test_regex should not contain any submatches
            $test_date =~ qr/^$test_datestring_regex$/;
            ok(scalar @- == 1 && scalar @+ == 1, ' with no sub-captures.');

            $test_formatted_datestring_regex =~ qr/^$test_datestring_regex$/;
            ok(scalar @- == 1 && scalar @+ == 1, ' with no sub-captures.');

            my $date_object = DatesRoleTester::parse_formatted_datestring_to_date($test_date);
            isa_ok($date_object, 'DateTime', $test_date);
            is($date_object->epoch, $dates_to_match{$test_date}, '... which represents the correct time.');
        }
    };

    subtest 'Working multi-dates' => sub {
        my @date_sets = ({
                src    => ['01/10/2014', '01/06/2014'],
                output => [1389312000,   1388966400],     # 10 jan; 6 jan
            },
            {
                src    => ['01/13/2014', '01/06/2014'],
                output => [1389571200,   1388966400],     # 13 jan; 6 jan
            },
            {
                src    => ['05/06/2014', '20/06/2014'],
                output => [1401926400,   1403222400],     # 5 jun; 20 jun
            },
            {
                src    => ['20/06/2014', '05/06/2014'],
                output => [1403222400,   1401926400],     # 20 jun; 5 jun
            },
            {
                src    => ['5/06/2014', '20/06/2014'],
                output => [1401926400,  1403222400],      # 5 jun; 20 jun
            },
            {
                src    => ['20/06/2014', '5/06/2014'],
                output => [1403222400,   1401926400],     # 20 jun; 5 jun
            },
            {
                src    => ['20-06-2014', '5-06-2014'],
                output => [1403222400,   1401926400],     # 20 jun; 5 jun
            },
            {
                src    => ['5-06-2014', '20-06-2014'],
                output => [1401926400,  1403222400],      # 5 jun; 20 jun
            },
            {
                src    => ['5-June-2014', '20-06-2014'],
                output => [1401926400,    1403222400],     # 5 jun; 20 jun
            },
            {
                src    => ['5-06-2014', '4th January 2013', '20-06-2014'],
                output => [1401926400,  1357257600,         1403222400],     # 5 jun; 4 jan, 20 jun
            },
            {
                src    => ['7-11-2015', 'august'],
                output => [1436572800,  1438387200],     # 11 jul; aug 1
            },
        );

        foreach my $set (@date_sets) {
            my @source = @{$set->{src}};
            eq_or_diff([map { $_->epoch } (DatesRoleTester::parse_all_datestrings_to_date(@source))],
                $set->{output}, '"' . join(', ', @source) . '": dates parsed correctly');
        }
    };

    subtest 'Strong dates and vague or relative dates mixed' => sub {
        set_fixed_time('2001-02-05T00:00:00Z');
        my @date_sets = (
            {
                src => ["1990-06-13", "december"],
                out => ['1990-06-13T00:00:00', '1990-12-01T00:00:00']
            },
#            {
#                src => ["1990-06-13", "last december"],
#                out => ['1990-06-13T00:00:00', '2000-12-01T00:00:00']
#            },
#            {
#                src => ["1990-06-13", "next december"],
#                out => ['1990-06-13T00:00:00', '2001-12-01T00:00:00']
#            },
            {
                src => ["1990-06-13", "today"],
                out => ['1990-06-13T00:00:00', '2001-02-05T00:00:00']
            },
            {
                src => ["1990-06-13", "tomorrow"],
                out => ['1990-06-13T00:00:00', '2001-02-06T00:00:00']
            },
            {
                src => ["1990-06-13", "yesterday"],
                out => ['1990-06-13T00:00:00', '2001-02-04T00:00:00']
            }
        );

        foreach my $set (@date_sets) {
            my @source = @{$set->{src}};
            my @expectation = @{$set->{out}};
            my @result = DatesRoleTester::parse_all_datestrings_to_date(@source);
            is_deeply(\@result, \@expectation, join(", ", @source));
        }

        restore_time();
    };

    subtest 'Relative naked months' => sub {

        my %time_strings = (
            "2015-01-13T00:00:00Z" => {
                src    => ['january', 'february'],
                output => ['2015-01-01T00:00:00', '2015-02-01T00:00:00'],
            },
            "2015-02-01T00:00:00Z" => {
                src    => ['january', 'february'],
                output => ['2016-01-01T00:00:00',  '2016-02-01T00:00:00'],
            },
            "2015-03-01T00:00:00Z" => {
                src    => ['january', 'february'],
                output => ['2016-01-01T00:00:00',  '2016-02-01T00:00:00'],
            },
            "2014-12-01T00:00:00Z" => {
                src    => ['january', 'february'],
                output => ['2015-01-01T00:00:00',  '2015-02-01T00:00:00'],
            },

        );

        foreach my $query_time (sort keys %time_strings) {
            set_fixed_time($query_time);

            my @source = @{$time_strings{$query_time}{src}};
            my @expectation = @{$time_strings{$query_time}{output}};
            my @result = DatesRoleTester::parse_all_datestrings_to_date(@source);

            is_deeply(\@result, \@expectation);
        }
    };

    subtest 'Invalid single dates' => sub {
        my %bad_strings_match = (
            '24/8'          => 0,
            '123'           => 0,
            '123-84-1'      => 0,
            '1st january'   => 0,
            '1/1/1'         => 0,
            '2014-13-13'    => 1,
            'Feb 38th 2015' => 1,
            '2014-02-29'    => 1,
        );

        foreach my $test_string (sort keys %bad_strings_match) {
            if ($bad_strings_match{$test_string}) {
                like($test_string, qr/^$test_formatted_datestring_regex$/, "$test_string matches formatted_datestring_regex");
            } else {
                unlike($test_string, qr/^$test_formatted_datestring_regex$/, "$test_string does not match formatted_datestring_regex");
            }

            my $result;
            lives_ok { $result = DatesRoleTester::parse_formatted_datestring_to_date($test_string) } '... and does not kill the parser.';
            is($result, undef, '... and returns undef to signal failure.');
        }
    };

    subtest 'Invalid multi-format' => sub {
        my @invalid_date_sets = (
            ['01/13/2014', '13/06/2014'],
            ['13/01/2014', '01/31/2014'],
            ['38/06/2014', '13/06/2014'],
            ['01/13/2014', '01/85/2014'],
            ['13/01/2014', '01/31/2014', '13/06/2014'],
            ['13/01/2014', '2001-01-01', '14/01/2014', '01/31/2014'],
        );

        foreach my $set (@invalid_date_sets) {
            my @source       = @$set;
            my @date_results = DatesRoleTester::parse_all_datestrings_to_date(@source);
            is(@date_results, 0, '"' . join(', ', @source) . '": cannot be parsed in combination.');
        }
    };

    subtest 'Valid standard string format' => sub {
        my %date_strings = (
            '01 Jan 2001' => ['2001-1-1',   'January 1st, 2001', '1st January, 2001'],
            '13 Jan 2014' => ['13/01/2014', '01/13/2014',        '13th Jan 2014'],
        );

        foreach my $result (sort keys %date_strings) {
            foreach my $test_string (@{$date_strings{$result}}) {
                is(DatesRoleTester::date_output_string($test_string), $result, $test_string . ' normalizes for output as ' . $result);
            }
        }
    };
    subtest 'Valid clock string format' => sub {
        my %date_strings = (
            '01 Jan 2012 00:01:20 UTC'   => ['01 Jan 2012 00:01:20 UTC', '01 Jan 2012 00:01:20 utc'],
            '22 Jun 1998 00:00:02 UTC'   => ['22 Jun 1998 00:00:02 GMT'],
            '07 Sep 2014 20:11:44 EST'   => ['07 Sep 2014 20:11:44 EST'],
            '07 Sep 2014 20:11:44 -0400' => ['07 Sep 2014 20:11:44 EDT'],
            '09 Aug 2014 18:20:00 UTC'   => ['09 Aug 2014 18:20:00'],
        );
        foreach my $result (sort keys %date_strings) {
            foreach my $test_string (@{$date_strings{$result}}) {
                is(DatesRoleTester::date_output_string($test_string, 1), $result, $test_string . ' normalizes for output as ' . $result);
            }
        }
    };
    subtest 'Invalid standard string format' => sub {
        my %bad_stuff = (
            'Empty string' => '',
            'Hashref'      => {},
            'Object'       => DatesRoleTester->new,
        );
        foreach my $description (sort keys %bad_stuff) {
            my $result;
            lives_ok { $result = DatesRoleTester::date_output_string($bad_stuff{$description}) } $description . ' does not kill the string output';
            is($result, '', '... and yields an empty string as a result');
        }
    };
    subtest 'Vague strings' => sub {
        my %time_strings = (
            '2000-08-01T00:00:00Z' => {
                'next december' => '01 Dec 2000',
                'last january'  => '01 Jan 2000',
                'this year'     => '01 Aug 2000',
                'june'          => '01 Jun 2001',
                'december 2015' => '01 Dec 2015',
                'june 2000'     => '01 Jun 2000',
                'jan'           => '01 Jan 2001',
                'august'        => '01 Aug 2000',
                'aug'           => '01 Aug 2000',
                'next jan'      => '01 Jan 2001',
                'last jan'      => '01 Jan 2000',
                'feb 2038'      => '01 Feb 2038',
                'next day'      => '02 Aug 2000',
            },
            '2015-12-01T00:00:00Z' => {
                'next december' => '01 Dec 2016',
                'last january'  => '01 Jan 2015',
                'june'          => '01 Jun 2016',
                'december'      => '01 Dec 2015',
                'december 2015' => '01 Dec 2015',
                'june 2000'     => '01 Jun 2000',
                'jan'           => '01 Jan 2016',
                'next jan'      => '01 Jan 2016',
                'last jan'      => '01 Jan 2015',
                'feb 2038'      => '01 Feb 2038',
                'now'           => '01 Dec 2015',
                'today'         => '01 Dec 2015',
                'current day'   => '01 Dec 2015',
                'next month'    => '01 Jan 2016',
                'this week'     => '01 Dec 2015',
                '1 month ago'   => '01 Nov 2015',
                '2 years ago'   => '01 Dec 2013'
            },
            '2000-01-01T00:00:00Z' => {
                'feb 21st'          => '21 Feb 2000',
                'january'           => '01 Jan 2000',
                '11th feb'          => '11 Feb 2000',
                'march 13'          => '13 Mar 2000',
                '12 march'          => '12 Mar 2000',
                'next week'         => '08 Jan 2000',
                'last week'         => '25 Dec 1999',
                'tomorrow'          => '02 Jan 2000',
                'yesterday'         => '31 Dec 1999',
                'last year'         => '01 Jan 1999',
                'next year'         => '01 Jan 2001',
                'in a day'          => '02 Jan 2000',
                'in a week'         => '08 Jan 2000',
                'in a month'        => '01 Feb 2000',
                'in a year'         => '01 Jan 2001',
                'in 1 day'          => '02 Jan 2000',
                'in 2 weeks'        => '15 Jan 2000',
                'in 3 months'       => '01 Apr 2000',
            },
            '2014-10-08T00:00:00Z' => {
                'next week'         => '15 Oct 2014',
                'this week'         => '08 Oct 2014',
                'last week'         => '01 Oct 2014',
                'next month'        => '08 Nov 2014',
                'this month'        => '08 Oct 2014',
                'last month'        => '08 Sep 2014',
                'next year'         => '08 Oct 2015',
                'this year'         => '08 Oct 2014',
                'last year'         => '08 Oct 2013',
                'december 2015'     => '01 Dec 2015',
                'march 13'          => '13 Mar 2014',
                'in a weeks time'   => '15 Oct 2014',
                '2 months ago'      => '08 Aug 2014',
                'in 2 years'        => '08 Oct 2016',
                'a week ago'        => '01 Oct 2014',
                'a month ago'       => '08 Sep 2014',
                'in 2 days'         => '10 Oct 2014'
            },
        );
        foreach my $query_time (sort keys %time_strings) {
            set_fixed_time($query_time);
            my %strings = %{$time_strings{$query_time}};
            foreach my $test_date (sort keys %strings) {
                like($test_date, qr/^$test_descriptive_datestring_regex$/, "$test_date matches the descriptive_datestring_regex");
                my $result = DatesRoleTester::parse_descriptive_datestring_to_date($test_date);
                isa_ok($result, 'DateTime', $test_date);
                is(DatesRoleTester::date_output_string($result), $strings{$test_date}, $test_date . ' relative to ' . $query_time);
            }
        }
        restore_time();
    };

    subtest 'Valid mixture of formatted and descriptive dates' => sub {
        set_fixed_time('2000-01-01T00:00:00Z');
        my %mixed_dates_to_test = (
            '2014-11-27'                => 1417046400,
            '1994-02-03T14:15:29'       => 760284929,
            'Sat, 09 Aug 2014 18:20:00' => 1407608400,
            '08-Feb-94 14:15:29 GMT'    => 760716929,
            '13/12/2011'                => 1323734400,
            '01/01/2001'                => 978307200,
            '29 June 2014'              => 1404000000,
            '05 Mar 1990'               => 636595200,
            'June 01 2012'              => 1338508800,
            'May 05 2011'               => 1304553600,
            'February 21st'             => 951091200,
            '11th feb'                  => 950227200,
            '11 march'                  => 952732800,
            '11 mar'                    => 952732800,
            'jun 21'                    => 961545600,
            'next january'              => 978307200,
            'december'                  => 975628800,
        );

        foreach my $test_mixed_date (sort keys %mixed_dates_to_test) {
            my $parsed_date_object = DatesRoleTester::parse_datestring_to_date($test_mixed_date);
            isa_ok($parsed_date_object, 'DateTime', $test_mixed_date);
            is($parsed_date_object->epoch, $mixed_dates_to_test{$test_mixed_date}, ' ... represents the correct time.');
        }

        restore_time();
    };

    subtest 'Relative dates with location' => sub {
        my $test_location = test_location('in');
        {
            package DDG::Goodie::FakerDater;
            use Moo;
            with 'DDG::GoodieRole::Dates';
            our $loc = $test_location;
            sub pds { shift; parse_datestring_to_date(@_); }
            1;
        }

        my $with_loc = new_ok('DDG::Goodie::FakerDater', [], 'With location');
        set_fixed_time('2013-12-31T23:00:00Z');
        my $today_obj;
        lives_ok { $today_obj = $with_loc->pds('today'); } 'Parsed out today at just before midnight UTC NYE, 2013';
        is($today_obj->time_zone_long_name, 'Asia/Kolkata', '... in our local time zone');
        is($today_obj->year,                2014,           '... where it is already 2014');
        is($today_obj->hms,                 '04:30:00',     '... for about 4.5 hours');
        is($today_obj->offset / 3600,       5.5,            '... which seems just about right.');

        restore_time();
    };
    subtest 'Valid Years' => sub {
        #my @valids = ('1', '0001', '9999', 2015, 1997);
        my @valids = ('1');
        my @invalids = (-1, 0, 10000);

        foreach my $case (@valids) {
            my $result;
            lives_ok {
                $result = DatesRoleTester::is_valid_year($case)
            };
            is($result, "1", "$case is a valid year");
        }

        foreach my $case (@invalids) {
            my $result;
            lives_ok {
                $result = DatesRoleTester::is_valid_year($case)
            };
            is($result, '', "$case is an invalid year");
        }
    }
};

subtest 'ImageLoader' => sub {

    subtest 'object with no share' => sub {
        # We have to wrap the function in a method in order to get the call-stack correct.
        { package ImgRoleTester; use Moo; with 'DDG::GoodieRole::ImageLoader'; sub img_wrap { shift; goodie_img_tag(@_); } 1; }

        my $no_share;
        subtest 'Initialization' => sub {
            $no_share = new_ok('ImgRoleTester', [], 'Applied to class');
        };

        subtest 'non-share enabled object attempts' => sub {
            my %no_deaths = (
                'undef'             => undef,
                'array ref'         => [],
                'killer code ref'   => sub { die },
                'with itself'       => $no_share,
                'empty hash ref'    => +{},
                'nonsense hash ref' => {ding => 'dong'},
                'proper'            => {filename => 'hi.jpg'},
            );
            foreach my $desc (sort keys %no_deaths) {
                lives_ok { $no_share->goodie_img_tag($no_deaths{$desc}) } $desc . ': does not die.';
            }
        };
    };
    subtest 'object with a share' => sub {
        our $b64_gif =
          'R0lGODlhEAAOALMAAOazToeHh0tLS/7LZv/0jvb29t/f3//Ub//ge8WSLf/rhf/3kdbW1mxsbP//mf///yH5BAAAAAAALAAAAAAQAA4AAARe8L1Ekyky67QZ1hLnjM5UUde0ECwLJoExKcppV0aCcGCmTIHEIUEqjgaORCMxIC6e0CcguWw6aFjsVMkkIr7g77ZKPJjPZqIyd7sJAgVGoEGv2xsBxqNgYPj/gAwXEQA7';
        our $final_src = 'src="data:image/gif;base64,' . $b64_gif;
        {

            package DDG::Goodie::ImgShareTester;
            use Moo;
            use HTML::Entities;
            use Path::Class;    # Hopefully the real share stays implemented this way.
            use MIME::Base64;
            with 'DDG::GoodieRole::ImageLoader';
            our $tmp_dir = Path::Class::tempdir(CLEANUP => 1);
            our $tmp_file = file(($tmp_dir->tempfile(TEMPLATE => 'img_XXXXXX', SUFFIX => '.gif'))[1]);
            # Always return the same file for our purposes here.
            sub share     { $tmp_file }
            sub html_enc  { encode_entities(@_) }                                             # Deal with silly symbol table twiddling.
            sub fill_temp { $tmp_file->spew(iomode => '>:bytes', decode_base64($b64_gif)) }
            sub kill_temp { undef $tmp_file }
            sub img_wrap { shift; goodie_img_tag(@_); }
            1;
        }

        my $with_share;
        subtest 'Initialization' => sub {
            $with_share = new_ok('DDG::Goodie::ImgShareTester', [], 'Applied to class');
        };

        subtest 'tag creation' => sub {
            my $filename = $with_share->share()->stringify;
            my $tag_content;
            lives_ok { $tag_content = $with_share->img_wrap({filename => $filename}) } 'Empty file does not die';
            is($tag_content, '', '... but returns empty tag.');
            $with_share->fill_temp;
            lives_ok { $tag_content = $with_share->img_wrap({filename => $filename}) } 'Newly filled file does not die';
            like($tag_content, qr/$final_src/, '... contains proper data');
            lives_ok { $tag_content = $with_share->img_wrap({filename => $filename, alt => 'Yo!'}) } 'With alt';
            like($tag_content, qr/$final_src/,  '... contains proper data');
            like($tag_content, qr/alt=\"Yo!\"/, '... and proper alt attribute');
            lives_ok { $tag_content = $with_share->img_wrap({filename => $filename, alt => 'Yo!', height => 12}) } 'Plus height';
            like($tag_content, qr/$final_src/,  '... contains proper data');
            like($tag_content, qr/alt="Yo!"/,   '... and proper alt attribute');
            like($tag_content, qr/height="12"/, '... and proper height attribute');
            lives_ok { $tag_content = $with_share->img_wrap({filename => $filename, alt => 'Yo!', height => 12, width => 10}) } 'Plus width';
            like($tag_content, qr/$final_src/,  '... contains proper data');
            like($tag_content, qr/alt="Yo!"/,   '... and proper alt attribute');
            like($tag_content, qr/height="12"/, '... and proper height attribute');
            like($tag_content, qr/width="10"/,  '... and proper width attribute');
            lives_ok { $tag_content = $with_share->img_wrap({filename => $filename, alt => 'hello"there!', height => 12, width => 10, class => 'smooth' }); } 'Plus class';
            like($tag_content, qr/$final_src/,              '... contains proper data');
            like($tag_content, qr/alt="hello&quot;there!"/, '... and proper alt attribute');
            like($tag_content, qr/height="12"/,             '... and proper height attribute');
            like($tag_content, qr/width="10"/,              '... and proper width attribute');
            like($tag_content, qr/class="smooth"/,          '... and proper class attribute');
            lives_ok { $tag_content = $with_share->img_wrap({filename => $filename, atl => 'Yo!', height => 12, width => 10, class => 'smooth'}) }
            'Any mispelled does not die';
            is($tag_content, '', '... but yields an empty tag');
            $with_share->kill_temp;
            lives_ok { $tag_content = $with_share->img_wrap({filename => $filename, alt => 'Yo!', height => 12, width => 10, class => 'smooth'}) }
            'File disappeared does not die';
            is($tag_content, '', '... but yields an empty tag');
        };
    };
};

my %wi_valid_queries = ();
subtest 'WhatIs' => sub {

    { package WhatIsTester; use Moo; with 'DDG::GoodieRole::WhatIs'; 1; }

    subtest 'Initialization' => sub {
        new_ok('WhatIsTester', [], 'Applied to a class');
    };

    sub build_value_test {
        my ($trans, $expecting_value, %forms) = @_;
        return sub {
            foreach my $key (keys %forms) {
                my $expected = $expecting_value ? $forms{$key} : undef;
                my $result = $trans->full_match($key);
                is($result->{'value'}, $expected, "Got an incorrect result for: $key");
            };
        };
    }

    sub entry_builder {
        my $func = shift;
        return sub {
            my $options = shift;
            no strict 'refs';
            my $f = \&{"WhatIsTester::$func"};
            my $wi = $f->(%{$options});
            isa_ok($wi, 'DDG::GoodieRole::WhatIs::Base', "$func");
            return $wi;
        };
    }
    sub wi_with_test { entry_builder('wi_custom')->(@_) };
    sub get_trans_with_test { entry_builder('wi_translation')->(@_) };

    sub add_valid_queries {
        my ($name, %queries) = @_;
        $wi_valid_queries{$name} = \%queries;
    }

    sub modifier_test {
        my $testf = shift;
        my %wi_options = (
            to => 'Goatee',
            from => 'Gribble',
            primary => qr/[10]{4} ?[10]{4}/,
            command => qr/lower ?case|lc/i,
            postfix_command => qr/lowercased/i,
            property => 'prime factor',
        );
        return sub {
            my %options = @_;
            my @use_options = @{$options{'use_options'} or []};
            my $use_groups = $options{'use_groups'};
            my @modifiers = @{$options{'modifiers'}};
            my $ignore_re = $options{'ignore'};
            my %valid_queries;
            foreach my $modifier (@modifiers) {
                %valid_queries = (%valid_queries, %{$wi_valid_queries{$modifier}});
            };
            my %wi_opts;
            @wi_opts{@use_options} = @wi_options{@use_options};
            my $wi = $testf->({
                groups => $use_groups,
                options => \%wi_opts,
            });
            subtest 'Valid Queries' => build_value_test($wi, 1, %valid_queries);
            my %invalid_queries = %{$options{'invalid_queries'}} if defined $options{'invalid_queries'};
            foreach my $invalid (keys %wi_valid_queries) {
                next if grep { $_ eq $invalid } @modifiers;
                if (defined $ignore_re) {
                    my %to_add;
                    foreach my $query (keys %{$wi_valid_queries{$invalid}}) {
                        next if $query =~ $ignore_re;
                        $to_add{$query} = $wi_valid_queries{$invalid}->{$query};
                    };
                    %invalid_queries = (%invalid_queries, %to_add);
                } else {
                    %invalid_queries = (%invalid_queries, %{$wi_valid_queries{$invalid}});
                };
            };
            subtest 'Invalid Queries' => build_value_test($wi, 0, %invalid_queries);
        };
    }
    sub test_custom { modifier_test(\&wi_with_test)->(@_) };
    sub test_translation { modifier_test(\&get_trans_with_test)->(@_) };

    add_valid_queries 'what is conversion' => (
        "What is foo in Goatee?"    => 'foo',
        "what is bar in Goatee"     => 'bar',
        "What is Goatee in Goatee?" => "Goatee",
    );
    add_valid_queries 'spoken translation' => (
        "How do I say foo in Goatee?"           => 'foo',
        "How would I say bar in Goatee"         => 'bar',
        "how to say baz in Goatee"              => 'baz',
        "How would you say bribble in Goatee"   => 'bribble',
        "How to say so much testing! in Goatee" => 'so much testing!',
    );
    add_valid_queries 'written translation' => (
        "How do I write foo in Goatee?"           => 'foo',
        "How would I write bar in Goatee"         => 'bar',
        "how to write baz in Goatee"              => 'baz',
        "How would you write bribble in Goatee"   => 'bribble',
        "How to write so much testing! in Goatee" => 'so much testing!',
    );
    add_valid_queries 'prefix imperative' => (
        'lowercase FOO'  => 'FOO',
        'lc bar'         => 'bar',
        'loWer case baz' => 'baz',
    );
    add_valid_queries 'meaning' => (
        'What is the meaning of bar' => 'bar',
        'What does foobar mean?'     => 'foobar',
    );
    add_valid_queries 'base conversion' => (
        '1011 0101 in Goatee' => '1011 0101',
        '11111111 to Goatee'  => '11111111',
    );
    add_valid_queries 'conversion from' => (
        'hello from Gribble' => 'hello',
    );
    add_valid_queries 'conversion to' => (
        'hello to Goatee' => 'hello',
    );
    add_valid_queries 'bidirectional conversion (only to)' => (
        'hello to Goatee'   => 'hello',
        'hello from Goatee' => 'hello',
    );
    add_valid_queries 'postfix imperative' => (
        'FriBble lowercased' => 'FriBble',
    );
    add_valid_queries 'targeted property' => (
        'What are the prime factors of 122?' => '122',
        'What is the prime factor of 3'      => '3',
        'prime factors of 27'                => '27',
        'prime factor of 7'                  => '7',
        'what is the prime factor for 29'    => '29',
        'what are the prime factors for 15'  => '15',
    );
    add_valid_queries 'language translation' => (
        'translate hello to Goatee' => 'hello',
    );

    sub hash_tester {
        my $hashf = shift;
        return sub {
            my %tests = @_;
            return sub {
                while (my ($test_name, $params) = each %tests) {
                    subtest $test_name => sub { $hashf->(%{$params}) };
                };
            };
        };
    }

    sub wi_translation_tests { hash_tester(\&test_translation)->(@_) }

    subtest 'Translations' => wi_translation_tests(
        'What is conversion' => {
            use_options => ['to'],
            modifiers => ['what is conversion'],
        },
        'Spoken' => {
            use_options => ['to'],
            use_groups => ['spoken'],
            modifiers => ['spoken translation', 'what is conversion'],
        },
        'Written' => {
            use_options => ['to'],
            use_groups => ['written'],
            modifiers => ['written translation', 'what is conversion'],
        },
        'Written and Spoken' => {
            use_options => ['to'],
            use_groups => ['written', 'spoken'],
            modifiers => ['spoken translation',
                          'written translation',
                          'what is conversion'],
        },
        'Language' => {
            use_options => ['to'],
            use_groups => ['language'],
            modifiers => ['language translation', 'what is conversion'],
        },
    );
    sub wi_custom_tests { hash_tester(\&test_custom)->(@_) }

    subtest 'Custom' => wi_custom_tests(
        'Meaning' => {
            use_groups => ['meaning'],
            modifiers => ['meaning'],
        },
        'Base Conversion' => {
            use_options => ['to', 'primary'],
            use_groups => ['conversion'],
            modifiers => ['base conversion'],
        },
        'Conversion to' => {
            use_options => ['to'],
            use_groups  => ['conversion', 'to'],
            modifiers   => ['conversion to'],
            ignore      => qr/ (to|in) /i,
        },
        'Conversion from' => {
            use_options => ['from'],
            use_groups  => ['conversion', 'from'],
            modifiers   => ['conversion from'],
            ignore      => qr/ (to|in) /i,
        },
        'Bidirectional Conversion' => {
            use_options => ['to', 'from'],
            use_groups  => ['bidirectional', 'conversion'],
            modifiers   => ['conversion from', 'conversion to'],
            ignore      => qr/ (to|in) /i,
        },
        'Bidirectional Conversion (only to)' => {
            use_options => ['to'],
            use_groups  => ['bidirectional', 'conversion'],
            modifiers   => ['base conversion', 'bidirectional conversion (only to)'],
            ignore      => qr/ (to|in) /i,
        },
        'Prefix Imperative' => {
            use_options => ['command'],
            use_groups => ['prefix', 'imperative'],
            modifiers => ['prefix imperative'],
        },
        'Postfix + Prefix Imperative' => {
            use_options => ['command', 'postfix_command'],
            use_groups => ['postfix', 'prefix', 'imperative'],
            modifiers => ['prefix imperative', 'postfix imperative'],
        },
        'Targeted Property' => {
            use_options => ['property'],
            use_groups  => ['property'],
            modifiers   => ['targeted property'],
        },
    );
};

done_testing;
