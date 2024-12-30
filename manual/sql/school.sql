--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4
-- Dumped by pg_dump version 17.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: alphabet_grade; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.alphabet_grade AS ENUM (
    'A+',
    'A',
    'B+',
    'B',
    'C+',
    'C',
    'D+',
    'D',
    'F'
);


ALTER TYPE public.alphabet_grade OWNER TO postgres;

--
-- Name: day_of_week; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.day_of_week AS ENUM (
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday'
);


ALTER TYPE public.day_of_week OWNER TO postgres;

--
-- Name: class_information_insert(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.class_information_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	tem CHAR(10);
BEGIN
	--In a semester, classes having the same location can not have the same time.
	SELECT clazz_id
	INTO tem
	FROM teach te
	JOIN study_time s USING (clazz_id, semester_id)
	WHERE s.semester_id = NEW.semester_id AND dow = NEW.dow AND room = NEW.room AND GREATEST(start_time, NEW.start_time) <= LEAST(finish_time, NEW.finish_time)
	LIMIT 1;
	
	IF tem IS NOT NULL
	THEN
		RAISE NOTICE 'Class % and class % have the same studying time and classroom', NEW.clazz_id, tem;
		RETURN NULL;
	END IF;

	-- There is no constraint in the timetable of a lecturer.
	SELECT clazz_id
	INTO tem
	FROM teach
	JOIN study_time s USING (clazz_id, semester_id)
	WHERE lecturer_id = NEW.lecturer_id AND s.semester_id = NEW.semester_id AND dow = NEW.dow AND GREATEST(start_time, NEW.start_time) <= LEAST(finish_time, NEW.finish_time)
	LIMIT 1;

	IF tem IS NOT NULL
	THEN 
		RAISE EXCEPTION 'Timetable constraint: class % and class %', NEW.clazz_id, tem;
		RETURN NULL;
	END IF;
	
	INSERT INTO study_time (clazz_id, semester_id, dow, start_time, finish_time)
	VALUES (NEW.clazz_id, NEW.semester_id, NEW.dow, NEW.start_time, NEW.finish_time);
	RAISE NOTICE 'Insert successfully.';

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.class_information_insert() OWNER TO postgres;

--
-- Name: class_information_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.class_information_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	institute_value_1 VARCHAR(10);
	institute_value_2 VARCHAR(10);
	tem CHAR(10);
BEGIN
	--In a semester, classes having the same location can not have the same time.
	SELECT clazz_id
	INTO tem
	FROM teach te
	JOIN study_time s USING (clazz_id, semester_id)
	WHERE clazz_id != NEW.clazz_id AND s.semester_id = NEW.semester_id AND dow = NEW.dow AND room = NEW.room AND GREATEST(start_time, NEW.start_time) <= LEAST(finish_time, NEW.finish_time)
	LIMIT 1;
	
	IF tem IS NOT NULL
	THEN
		RAISE NOTICE 'Class % and class % have the same studying time and classroom', NEW.clazz_id, tem;
		RETURN NULL;
	END IF;

	-- Lecturer and subject must have the same insitute
	SELECT subject_id INTO tem FROM clazz WHERE clazz_id = NEW.clazz_id;
	SELECT institute_id INTO institute_value_1 FROM subject WHERE subject_id = tem;
	SELECT institute_id INTO institute_value_2 FROM lecturer WHERE lecturer_id = NEW.lecturer_id;
	
	IF institute_value_1 != institute_value_2
	THEN
		RAISE NOTICE 'Class % violates institute contraint.', NEW.clazz_id;
		RETURN NULL;
	END IF;

	-- There is no constraint in the timetable of a lecturer.
	SELECT clazz_id
	INTO tem
	FROM teach
	JOIN study_time s USING (clazz_id, semester_id)
	WHERE clazz_id != NEW.clazz_id AND lecturer_id = NEW.lecturer_id AND s.semester_id = NEW.semester_id AND dow = NEW.dow AND GREATEST(start_time, NEW.start_time) <= LEAST(finish_time, NEW.finish_time)
	LIMIT 1;

	IF tem IS NOT NULL
	THEN 
		RAISE EXCEPTION 'Timetable constraint: class % and class %', NEW.clazz_id, tem;
		RETURN NULL;
	END IF;
	
	-- First: Enter the clazz_id and semester (in WHERE)
	-- Second: Update
	UPDATE teach
    SET lecturer_id = COALESCE(NULLIF(NEW.lecturer_id, OLD.lecturer_id), OLD.lecturer_id),
        max_student = COALESCE(NULLIF(NEW.max_student, OLD.max_student), OLD.max_student),
        room = COALESCE(NULLIF(NEW.room, OLD.room), OLD.room)
	WHERE clazz_id = NEW.clazz_id AND semester_id = NEW.semester_id;
			
	UPDATE study_time
    SET dow = COALESCE(NULLIF(NEW.dow, OLD.dow), OLD.dow),
        start_time = COALESCE(NULLIF(NEW.start_time, OLD.start_time), OLD.start_time),
        finish_time = COALESCE(NULLIF(NEW.finish_time, OLD.finish_time), OLD.finish_time)
    WHERE clazz_id = NEW.clazz_id AND semester_id = NEW.semester_id;
				
	RAISE NOTICE 'Update successfully.';
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.class_information_update() OWNER TO postgres;

--
-- Name: enroll_insert(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.enroll_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	subject_id_value VARCHAR(7);
	rc RECORD;
	tem CHAR(6);
BEGIN
	--For a subject, a student is not allowed to enroll more than one class in a semester
	SELECT subject_id INTO subject_id_value FROM clazz WHERE clazz_id = NEW.clazz_id;
	IF EXISTS (
		SELECT 1
		FROM enroll
		JOIN clazz USING (clazz_id)
		WHERE student_id = NEW.student_id AND semester_id = NEW.semester_id AND subject_id = subject_id_value)
	THEN
		RAISE EXCEPTION 'You enrolled subject % in this semester.', subject_id_value;
		RETURN NULL;
	END IF;

	-- Students are not allowed to enroll in full classes
	IF EXISTS (
		SELECT 1
		FROM class_information
		WHERE clazz_id = NEW.clazz_id AND semester_id = NEW.semester_id AND current_student_number IS NOT NULL AND current_student_number >= max_student)
	THEN
		RAISE EXCEPTION 'Class % is full.', NEW.clazz_id;
		RETURN NULL;
	END IF;

	-- There is no constraint in the timetable of a student.
	-- Tạo bảng tạm lưu các lớp mà sinh viên X đã đăng ký trong kỳ Y
	CREATE TEMP TABLE temp_table AS
	SELECT st.*
	FROM enroll e
	JOIN study_time st USING (clazz_id, semester_id)
	WHERE student_id = NEW.student_id AND semester_id = NEW.semester_id;

	-- 
	FOR rc IN
		SELECT dow, start_time, finish_time
		FROM study_time
		WHERE clazz_id = NEW.clazz_id AND semester_id = NEW.semester_id
	LOOP
		SELECT clazz_id
		INTO tem
		FROM temp_table
		WHERE dow = rc.dow AND GREATEST(start_time, rc.start_time) <= LEAST(finish_time, rc.finish_time)
		LIMIT 1;

		IF tem IS NOT NULL
		THEN 
			DROP TABLE temp_table;
			RAISE EXCEPTION 'Timetable constraint: class % and class %', NEW.clazz_id, tem;
			RETURN NULL;
		END IF;
	END LOOP;
	DROP TABLE temp_table;
	
	RAISE NOTICE 'Enroll successfully.';
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.enroll_insert() OWNER TO postgres;

--
-- Name: getsemester(date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.getsemester(in_date date) RETURNS character
    LANGUAGE plpgsql
    AS $$
DECLARE
   ret_date CHAR(5);
BEGIN
	SELECT semester_id
	INTO ret_date
	FROM semester 
	WHERE in_date BETWEEN start_semester_date AND finish_semester_date;
    RETURN ret_date;
END;
$$;


ALTER FUNCTION public.getsemester(in_date date) OWNER TO postgres;

--
-- Name: give_conduct_point_insert(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.give_conduct_point_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN 	
	IF (
		SELECT institute_id
		FROM form_teacher
		WHERE formteacher_id = NEW.formteacher_id
	) IS DISTINCT FROM (
		SELECT institute_id
		FROM student
		WHERE student_id = NEW.student_id
	)
	THEN
		RAISE EXCEPTION 'Violate institute constraint';
		RETURN NULL;
	ELSE
		RAISE NOTICE 'Insert successfully';
		RETURN NEW;
	END IF;
END;
$$;


ALTER FUNCTION public.give_conduct_point_insert() OWNER TO postgres;

--
-- Name: insert_study_time(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.insert_study_time() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN
	
	IF EXISTS (
		SELECT
		FROM study_time
		WHERE clazz_id = NEW.clazz_id AND semester_id = NEW.semester_id AND dow = NEW.dow AND GREATEST(start_time, NEW.start_time) <= LEAST(finish_time, NEW.finish_time)
		LIMIT 1)
	THEN
		RAISE EXCEPTION 'Class % is overlapped.', NEW.clazz_id;
		RETURN NULL;
	END IF;
	
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.insert_study_time() OWNER TO postgres;

--
-- Name: teach_insert(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.teach_insert() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	tem CHAR(10);
	institute_value_1 VARCHAR(10);
	institute_value_2 VARCHAR(10);
BEGIN
	SELECT subject_id INTO tem FROM clazz WHERE clazz_id = NEW.clazz_id;
	SELECT institute_id INTO institute_value_1 FROM subject WHERE subject_id = tem;
	SELECT institute_id INTO institute_value_2 FROM lecturer WHERE lecturer_id = NEW.lecturer_id;
	
	IF institute_value_1 != institute_value_2
	THEN
		RAISE NOTICE 'Class % violates institute contraint.', NEW.clazz_id;
		RETURN NULL;
	END IF;

	RETURN NEW;
END;
$$;


ALTER FUNCTION public.teach_insert() OWNER TO postgres;

--
-- Name: update_study_time(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_study_time() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ 
BEGIN
	
	IF EXISTS (
		SELECT
		FROM study_time
		WHERE clazz_id = OLD.clazz_id AND semester_id = OLD.semester_id AND dow = NEW.dow AND GREATEST(start_time, NEW.start_time) <= LEAST(finish_time, NEW.finish_time) 
			  AND start_time != OLD.start_time -- start_time != OLD.start_time để loại đi OLD record
		LIMIT 1)
	THEN
		RAISE EXCEPTION 'Class % is overlapped.', NEW.clazz_id;
		RETURN NULL;
	END IF;
	
	RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_study_time() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: clazz; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clazz (
    clazz_id character(6) NOT NULL,
    subject_id character varying(7)
);


ALTER TABLE public.clazz OWNER TO postgres;

--
-- Name: enroll; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.enroll (
    student_id character(8) NOT NULL,
    clazz_id character(6) NOT NULL,
    semester_id character(5) NOT NULL,
    midpoint numeric(3,1),
    finalpoint numeric(3,1),
    CONSTRAINT enroll_finalpoint_check CHECK (((finalpoint >= 0.0) AND (finalpoint <= 10.0))),
    CONSTRAINT enroll_midpoint_check CHECK (((midpoint >= 0.0) AND (midpoint <= 10.0)))
);


ALTER TABLE public.enroll OWNER TO postgres;

--
-- Name: grade_rule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.grade_rule (
    alphabet_point public.alphabet_grade,
    four_scale numeric(3,1),
    ten_scale_from numeric(3,1),
    ten_scale_to numeric(3,1),
    CONSTRAINT check_grade CHECK ((ten_scale_from < ten_scale_to)),
    CONSTRAINT grade_rule_four_scale_check CHECK (((four_scale <= 4.0) AND (four_scale >= 0.0))),
    CONSTRAINT grade_rule_ten_scale_from_check CHECK (((ten_scale_from <= 10.0) AND (ten_scale_from >= (0)::numeric))),
    CONSTRAINT grade_rule_ten_scale_to_check CHECK (((ten_scale_to <= 10.0) AND (ten_scale_to >= (0)::numeric)))
);


ALTER TABLE public.grade_rule OWNER TO postgres;

--
-- Name: subject; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.subject (
    subject_id character varying(7) NOT NULL,
    subject_name character varying(50),
    institute_id character varying(8),
    credit smallint,
    final_coefficient numeric(3,1),
    CONSTRAINT subject_credit_check CHECK ((credit >= 0)),
    CONSTRAINT subject_final_coefficient_check CHECK (((final_coefficient < (1)::numeric) AND (final_coefficient > (0)::numeric)))
);


ALTER TABLE public.subject OWNER TO postgres;

--
-- Name: calculate_grade_in_each_class; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.calculate_grade_in_each_class AS
 WITH tem AS (
         SELECT en.student_id,
            cl.clazz_id,
            cl.subject_id,
            en.semester_id,
            sub.credit,
            ((en.midpoint * ((1)::numeric - sub.final_coefficient)) + (en.finalpoint * sub.final_coefficient)) AS class_point
           FROM ((public.enroll en
             JOIN public.clazz cl USING (clazz_id))
             JOIN public.subject sub USING (subject_id))
        )
 SELECT tem.student_id,
    tem.clazz_id,
    tem.subject_id,
    tem.semester_id,
    tem.credit,
    tem.class_point,
    grade_rule.alphabet_point,
    grade_rule.four_scale
   FROM (tem
     JOIN public.grade_rule ON (((tem.class_point >= grade_rule.ten_scale_from) AND (tem.class_point <= grade_rule.ten_scale_to))));


ALTER VIEW public.calculate_grade_in_each_class OWNER TO postgres;

--
-- Name: calculate_gpa; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.calculate_gpa AS
 SELECT student_id,
    semester_id,
    (sum((four_scale * (credit)::numeric)) / (sum(credit))::numeric) AS gpa
   FROM public.calculate_grade_in_each_class
  GROUP BY student_id, semester_id;


ALTER VIEW public.calculate_gpa OWNER TO postgres;

--
-- Name: student_number_in_a_semester; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.student_number_in_a_semester AS
 SELECT clazz_id,
    semester_id,
    count(*) AS current_student_number
   FROM public.enroll
  GROUP BY clazz_id, semester_id;


ALTER VIEW public.student_number_in_a_semester OWNER TO postgres;

--
-- Name: study_time; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.study_time (
    clazz_id character(6) NOT NULL,
    semester_id character(5) NOT NULL,
    dow public.day_of_week NOT NULL,
    start_time time without time zone NOT NULL,
    finish_time time without time zone,
    CONSTRAINT check_time_clazz CHECK ((start_time < finish_time))
);


ALTER TABLE public.study_time OWNER TO postgres;

--
-- Name: teach; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.teach (
    clazz_id character(6) NOT NULL,
    semester_id character(5) NOT NULL,
    lecturer_id character(6),
    room character varying(10),
    max_student smallint,
    CONSTRAINT teach_max_student_check CHECK ((max_student > 0))
);


ALTER TABLE public.teach OWNER TO postgres;

--
-- Name: class_information; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.class_information AS
 SELECT te.clazz_id,
    te.semester_id,
    clazz.subject_id,
    te.lecturer_id,
    sb.subject_name,
    te.max_student,
    COALESCE(sn.current_student_number, (0)::bigint) AS current_student_number,
    te.room,
    study_time.dow,
    study_time.start_time,
    study_time.finish_time
   FROM ((((public.teach te
     JOIN public.study_time USING (clazz_id, semester_id))
     JOIN public.clazz USING (clazz_id))
     LEFT JOIN public.student_number_in_a_semester sn USING (clazz_id, semester_id))
     JOIN public.subject sb USING (subject_id));


ALTER VIEW public.class_information OWNER TO postgres;

--
-- Name: form_teacher; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.form_teacher (
    formteacher_id character(6) NOT NULL,
    formteacher_name character varying(50),
    gender character(1),
    phone_number character varying(15),
    institute_id character varying(8),
    username character varying(50),
    pword character varying(20),
    CONSTRAINT form_teacher_gender_check CHECK (((gender = 'F'::bpchar) OR (gender = 'M'::bpchar)))
);


ALTER TABLE public.form_teacher OWNER TO postgres;

--
-- Name: give_conduct_point; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.give_conduct_point (
    formteacher_id character(6) NOT NULL,
    student_id character(8) NOT NULL,
    semester_id character(5) NOT NULL,
    conduct_point smallint,
    CONSTRAINT give_conduct_point_conduct_point_check CHECK (((conduct_point >= 0) AND (conduct_point <= 100)))
);


ALTER TABLE public.give_conduct_point OWNER TO postgres;

--
-- Name: headmaster; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.headmaster (
    headmaster_id character(4) NOT NULL,
    institute_id character varying(8),
    headmaster_name character varying(50),
    gender character(1),
    phone_number character varying(15),
    username character varying(50),
    pword character varying(20),
    CONSTRAINT headmaster_gender_check CHECK (((gender = 'F'::bpchar) OR (gender = 'M'::bpchar)))
);


ALTER TABLE public.headmaster OWNER TO postgres;

--
-- Name: institute; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.institute (
    institute_id character varying(8) NOT NULL,
    institute_name character varying(50),
    address character varying(150)
);


ALTER TABLE public.institute OWNER TO postgres;

--
-- Name: lecturer; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lecturer (
    lecturer_id character(6) NOT NULL,
    lecturer_name character varying(50),
    gender character(1),
    phone_number character varying(15),
    institute_id character varying(8),
    username character varying(50),
    pword character varying(20),
    CONSTRAINT lecturer_gender_check CHECK (((gender = 'F'::bpchar) OR (gender = 'M'::bpchar)))
);


ALTER TABLE public.lecturer OWNER TO postgres;

--
-- Name: semester; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.semester (
    semester_id character(5) NOT NULL,
    start_enroll_time timestamp without time zone,
    finish_enroll_time timestamp without time zone,
    start_givepoint_time timestamp without time zone,
    finish_givepoint_time timestamp without time zone,
    start_semester_date date,
    finish_semester_date date,
    CONSTRAINT check_time CHECK (((start_enroll_time < finish_enroll_time) AND (start_givepoint_time < finish_givepoint_time) AND (finish_enroll_time < start_givepoint_time)))
);


ALTER TABLE public.semester OWNER TO postgres;

--
-- Name: student; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student (
    student_id character(8) NOT NULL,
    citizen_id character(12) NOT NULL,
    student_name character varying(50),
    gender character(1),
    dob date,
    major character varying(50),
    institute_id character varying(8),
    username character varying(50),
    pword character varying(20),
    CONSTRAINT student_gender_check CHECK (((gender = 'F'::bpchar) OR (gender = 'M'::bpchar)))
);


ALTER TABLE public.student OWNER TO postgres;

--
-- Name: subject_grades_of_students; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.subject_grades_of_students AS
 WITH tem AS (
         SELECT calculate_grade_in_each_class.student_id,
            calculate_grade_in_each_class.subject_id,
            max(calculate_grade_in_each_class.class_point) AS max_point
           FROM public.calculate_grade_in_each_class
          GROUP BY calculate_grade_in_each_class.student_id, calculate_grade_in_each_class.subject_id
        )
 SELECT t1.student_id,
    t1.clazz_id,
    t1.subject_id,
    t1.semester_id,
    t1.credit,
    t1.class_point,
    t1.alphabet_point,
    t1.four_scale
   FROM (public.calculate_grade_in_each_class t1
     JOIN tem t2 ON (((t1.student_id = t2.student_id) AND ((t1.subject_id)::text = (t2.subject_id)::text) AND (t1.class_point = t2.max_point))));


ALTER VIEW public.subject_grades_of_students OWNER TO postgres;

--
-- Name: tutor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tutor (
    tutor_id character(8) NOT NULL,
    father_name character varying(50),
    father_dob date,
    father_job character varying(30),
    father_phonenumber character varying(15),
    mother_name character varying(50),
    mother_dob date,
    mother_job character varying(30),
    mother_phonenumber character varying(15)
);


ALTER TABLE public.tutor OWNER TO postgres;

--
-- Data for Name: clazz; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clazz (clazz_id, subject_id) FROM stdin;
100001	ED0001
100002	ED0002
200001	EE0001
300001	EP0001
300002	EP0002
400001	IT0001
500001	LS0001
600001	ME0001
600002	ME0002
700001	MI0001
700002	MI0001
700003	MI0001
710001	MI0002
710002	MI0002
710003	MI0002
720001	MI0003
720002	MI0003
720003	MI0003
730001	MI0004
730002	MI0004
730003	MI0004
740001	MI0005
740002	MI0005
740003	MI0005
800001	SM0001
750001	MI0006
750002	MI0006
410001	IT0002
410002	IT0002
420003	IT0003
420004	IT0003
400005	IT0004
400006	IT0004
400007	IT0005
400008	IT0005
900001	FL0001
900002	FL0001
900003	FL0002
900004	FL0002
100003	ED0001
100004	ED0001
100005	ED0002
\.


--
-- Data for Name: enroll; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.enroll (student_id, clazz_id, semester_id, midpoint, finalpoint) FROM stdin;
20231389	400001	20241	8.5	9.0
20241256	400001	20241	7.0	7.5
20221231	400001	20241	5.5	6.0
20221234	400001	20241	8.0	8.5
20221243	400001	20241	9.0	9.5
20221245	400001	20241	6.5	7.0
20221452	400001	20241	7.5	8.0
20221468	400001	20241	8.5	9.0
20221489	400001	20241	5.0	6.0
20221987	400001	20241	6.5	7.5
20222134	400001	20241	7.0	8.0
20222345	400001	20241	8.0	8.5
20223080	400001	20241	9.5	10.0
20223081	400001	20241	7.0	7.5
20223210	400001	20241	6.5	7.0
20223456	400001	20241	5.0	6.0
20223567	400001	20241	7.5	8.0
20223645	400001	20241	8.5	9.0
20223987	400001	20241	6.0	6.5
20224321	400001	20241	9.0	9.5
20224356	400001	20241	8.0	8.5
20224456	400001	20241	7.0	7.5
20224521	400001	20241	6.0	6.5
20224567	400001	20241	8.5	9.0
20224612	400001	20241	9.0	9.5
20225431	400001	20241	7.5	8.0
20225432	400001	20241	6.5	7.0
20225478	400001	20241	8.0	8.5
20225678	400001	20241	5.5	6.5
20225736	400001	20241	7.0	7.5
20226216	400001	20241	8.5	9.0
20226547	400001	20241	6.5	7.0
20226741	400001	20241	8.0	8.5
20226783	400001	20241	7.5	8.0
20226789	400001	20241	6.0	6.5
20227635	400001	20241	5.5	6.0
20227636	400001	20241	7.0	7.5
20227654	400001	20241	9.5	10.0
20227689	400001	20241	8.0	8.5
20227823	400001	20241	6.5	7.0
20227890	400001	20241	7.5	8.0
20227891	400001	20241	8.5	9.0
20228734	400001	20241	5.0	5.5
20228865	400001	20241	7.0	7.5
20228891	400001	20241	8.0	8.5
20229123	400001	20241	6.5	7.0
20229378	400001	20241	9.0	9.5
20231245	400001	20241	7.5	8.0
20231389	700001	20241	8.5	9.0
20241256	700001	20241	7.0	7.5
20221231	700001	20241	5.5	6.0
20221234	700001	20241	8.0	8.5
20221243	700001	20241	9.0	9.5
20221245	700001	20241	6.5	7.0
20221452	700001	20241	7.5	8.0
20221468	700001	20241	8.5	9.0
20221489	700001	20241	5.0	6.0
20221987	700001	20241	6.5	7.5
20222134	700001	20241	7.0	8.0
20222345	700001	20241	8.0	8.5
20223080	700001	20241	9.5	10.0
20223081	700001	20241	7.0	7.5
20223210	700001	20241	6.5	7.0
20223456	700001	20241	5.0	6.0
20223567	700001	20241	7.5	8.0
20223645	700001	20241	8.5	9.0
20223987	700001	20241	6.0	6.5
20224321	700001	20241	9.0	9.5
20224356	700001	20241	8.0	8.5
20224456	700001	20241	7.0	7.5
20224521	700001	20241	6.0	6.5
20224567	700001	20241	8.5	9.0
20224612	700001	20241	9.0	9.5
20225431	700001	20241	7.5	8.0
20225432	700001	20241	6.5	7.0
20225478	700001	20241	8.0	8.5
20225678	700001	20241	5.5	6.5
20225736	700001	20241	7.0	7.5
20226216	700001	20241	8.5	9.0
20226547	700001	20241	6.5	7.0
20226741	700001	20241	8.0	8.5
20226783	700001	20241	7.5	8.0
20226789	700001	20241	6.0	6.5
20227635	700001	20241	5.5	6.0
20227636	700001	20241	7.0	7.5
20227654	700001	20241	9.5	10.0
20227689	700001	20241	8.0	8.5
20227823	700001	20241	6.5	7.0
20227890	700001	20241	7.5	8.0
20227891	700001	20241	8.5	9.0
20228734	700001	20241	5.0	5.5
20228865	700001	20241	7.0	7.5
20228891	700001	20241	8.0	8.5
20229123	700001	20241	6.5	7.0
20229378	700001	20241	9.0	9.5
20231245	700001	20241	7.5	8.0
20231389	710001	20241	8.5	9.0
20241256	710001	20241	7.0	7.5
20221231	710001	20241	5.5	6.0
20221234	710001	20241	8.0	8.5
20221243	710001	20241	9.0	9.5
20221245	710001	20241	6.5	7.0
20221452	710001	20241	7.5	8.0
20221468	710001	20241	8.5	9.0
20221489	710001	20241	5.0	6.0
20221987	710001	20241	6.5	7.5
20222134	710001	20241	7.0	8.0
20222345	710001	20241	8.0	8.5
20223080	710001	20241	9.5	10.0
20223081	710001	20241	7.0	7.5
20223210	710001	20241	6.5	7.0
20223456	710001	20241	5.0	6.0
20223567	710001	20241	7.5	8.0
20223645	710001	20241	8.5	9.0
20223987	710001	20241	6.0	6.5
20224321	710001	20241	9.0	9.5
20224356	710001	20241	8.0	8.5
20224456	710001	20241	7.0	7.5
20224521	710001	20241	6.0	6.5
20224567	710001	20241	8.5	9.0
20224612	710001	20241	9.0	9.5
20225431	710001	20241	7.5	8.0
20225432	710001	20241	6.5	7.0
20225478	710001	20241	8.0	8.5
20225678	710001	20241	5.5	6.5
20225736	710001	20241	7.0	7.5
20226216	710001	20241	8.5	9.0
20226547	710001	20241	6.5	7.0
20226741	710001	20241	8.0	8.5
20226783	710001	20241	7.5	8.0
20226789	710001	20241	6.0	6.5
20227635	710001	20241	5.5	6.0
20227636	710001	20241	7.0	7.5
20227654	710001	20241	9.5	10.0
20227689	710001	20241	8.0	8.5
20227823	710001	20241	6.5	7.0
20227890	710001	20241	7.5	8.0
20227891	710001	20241	8.5	9.0
20228734	710001	20241	5.0	5.5
20228865	710001	20241	7.0	7.5
20228891	710001	20241	8.0	8.5
20229123	710001	20241	6.5	7.0
20229378	710001	20241	9.0	9.5
20231245	710001	20241	7.5	8.0
20231389	900003	20241	8.5	9.0
20241256	900003	20241	7.0	7.5
20221231	900003	20241	5.5	6.0
20221234	900003	20241	8.0	8.5
20221243	900003	20241	9.0	9.5
20221245	900003	20241	6.5	7.0
20221452	900003	20241	7.5	8.0
20221468	900003	20241	8.5	9.0
20221489	900003	20241	5.0	6.0
20221987	900003	20241	6.5	7.5
20222134	900003	20241	7.0	8.0
20222345	900003	20241	8.0	8.5
20223080	900003	20241	9.5	10.0
20223081	900003	20241	7.0	7.5
20223210	900003	20241	6.5	7.0
20223456	900003	20241	5.0	6.0
20223567	900003	20241	7.5	8.0
20223645	900003	20241	8.5	9.0
20223987	900003	20241	6.0	6.5
20224321	900003	20241	9.0	9.5
20224356	900003	20241	8.0	8.5
20224456	900003	20241	7.0	7.5
20224521	900003	20241	6.0	6.5
20224567	900003	20241	8.5	9.0
20224612	900003	20241	9.0	9.5
20225431	900003	20241	7.5	8.0
20225432	900003	20241	6.5	7.0
20225478	900003	20241	8.0	8.5
20225678	900003	20241	5.5	6.5
20225736	900003	20241	7.0	7.5
20226216	900003	20241	8.5	9.0
20226547	900003	20241	6.5	7.0
20226741	900003	20241	8.0	8.5
20226783	900003	20241	7.5	8.0
20226789	900003	20241	6.0	6.5
20227635	900003	20241	5.5	6.0
20227636	900003	20241	7.0	7.5
20227654	900003	20241	9.5	10.0
20227689	900003	20241	8.0	8.5
20227823	900003	20241	6.5	7.0
20227890	900003	20241	7.5	8.0
20227891	900003	20241	8.5	9.0
20228734	900003	20241	5.0	5.5
20228865	900003	20241	7.0	7.5
20228891	900003	20241	8.0	8.5
20229123	900003	20241	6.5	7.0
20229378	900003	20241	9.0	9.5
20231245	900003	20241	7.5	8.0
20231389	750001	20241	8.5	9.0
20241256	750001	20241	7.0	7.5
20221231	750001	20241	5.5	6.0
20221234	750001	20241	8.0	8.5
20221243	750001	20241	9.0	9.5
20221245	750001	20241	6.5	7.0
20221452	750001	20241	7.5	8.0
20221468	750001	20241	8.5	9.0
20221489	750001	20241	5.0	6.0
20221987	750001	20241	6.5	7.5
20222134	750001	20241	7.0	8.0
20222345	750001	20241	8.0	8.5
20223080	750001	20241	9.5	10.0
20223081	750001	20241	7.0	7.5
20223210	750001	20241	6.5	7.0
20223456	750001	20241	5.0	6.0
20223567	750001	20241	7.5	8.0
20223645	750001	20241	8.5	9.0
20223987	750001	20241	6.0	6.5
20224321	750001	20241	9.0	9.5
20224356	750001	20241	8.0	8.5
20224456	750001	20241	7.0	7.5
20224521	750001	20241	6.0	6.5
20224567	750001	20241	8.5	9.0
20224612	750001	20241	9.0	9.5
20225431	750001	20241	7.5	8.0
20225432	750001	20241	6.5	7.0
20225478	750001	20241	8.0	8.5
20225678	750001	20241	5.5	6.5
20225736	750001	20241	7.0	7.5
20226216	750001	20241	8.5	9.0
20226547	750001	20241	6.5	7.0
20226741	750001	20241	8.0	8.5
20226783	750001	20241	7.5	8.0
20226789	750001	20241	6.0	6.5
20227635	750001	20241	5.5	6.0
20227636	750001	20241	7.0	7.5
20227654	750001	20241	9.5	10.0
20227689	750001	20241	8.0	8.5
20227823	750001	20241	6.5	7.0
20227890	750001	20241	7.5	8.0
20227891	750001	20241	8.5	9.0
20228734	750001	20241	5.0	5.5
20228865	750001	20241	7.0	7.5
20228891	750001	20241	8.0	8.5
20229123	750001	20241	6.5	7.0
20229378	750001	20241	9.0	9.5
20231245	750001	20241	7.5	8.0
20231389	730001	20241	8.5	9.0
20241256	730001	20241	7.0	7.5
20221231	730001	20241	5.5	6.0
20221234	730001	20241	8.0	8.5
20221243	730001	20241	9.0	9.5
20221245	730001	20241	6.5	7.0
20221452	730001	20241	7.5	8.0
20221468	730001	20241	8.5	9.0
20221489	730001	20241	5.0	6.0
20221987	730001	20241	6.5	7.5
20222134	730001	20241	7.0	8.0
20222345	730001	20241	8.0	8.5
20223080	730001	20241	9.5	10.0
20223081	730001	20241	7.0	7.5
20223210	730001	20241	6.5	7.0
20223456	730001	20241	5.0	6.0
20223567	730001	20241	7.5	8.0
20223645	730001	20241	8.5	9.0
20223987	730001	20241	6.0	6.5
20224321	730001	20241	9.0	9.5
20224356	730001	20241	8.0	8.5
20224456	730001	20241	7.0	7.5
20224521	730001	20241	6.0	6.5
20224567	730001	20241	8.5	9.0
20224612	730001	20241	9.0	9.5
20225431	730001	20241	7.5	8.0
20225432	730001	20241	6.5	7.0
20225478	730001	20241	8.0	8.5
20225678	730001	20241	5.5	6.5
20225736	730001	20241	7.0	7.5
20226216	730001	20241	8.5	9.0
20226547	730001	20241	6.5	7.0
20226741	730001	20241	8.0	8.5
20226783	730001	20241	7.5	8.0
20226789	730001	20241	6.0	6.5
20227635	730001	20241	5.5	6.0
20227636	730001	20241	7.0	7.5
20227654	730001	20241	9.5	10.0
20227689	730001	20241	8.0	8.5
20227823	730001	20241	6.5	7.0
20227890	730001	20241	7.5	8.0
20227891	730001	20241	8.5	9.0
20228734	730001	20241	5.0	5.5
20228865	730001	20241	7.0	7.5
20228891	730001	20241	8.0	8.5
20229123	730001	20241	6.5	7.0
20229378	730001	20241	9.0	9.5
20231245	730001	20241	7.5	8.0
20231389	100001	20241	8.5	9.0
20241256	100001	20241	7.0	7.5
20221231	100001	20241	5.5	6.0
20221234	100001	20241	8.0	8.5
20221243	100001	20241	9.0	9.5
20221245	100001	20241	6.5	7.0
20221452	100001	20241	7.5	8.0
20221468	100001	20241	8.5	9.0
20221489	100001	20241	5.0	6.0
20221987	100001	20241	6.5	7.5
20222134	100001	20241	7.0	8.0
20222345	100001	20241	8.0	8.5
20223080	100001	20241	9.5	10.0
20223081	100001	20241	7.0	7.5
20223210	100001	20241	6.5	7.0
20223456	100001	20241	5.0	6.0
20223567	100001	20241	7.5	8.0
20223645	100001	20241	8.5	9.0
20223987	100001	20241	6.0	6.5
20224321	100001	20241	9.0	9.5
20224356	100001	20241	8.0	8.5
20224456	100001	20241	7.0	7.5
20224521	100001	20241	6.0	6.5
20224567	100001	20241	8.5	9.0
20224612	100001	20241	9.0	9.5
20225431	100001	20241	7.5	8.0
20225432	100001	20241	6.5	7.0
20225478	100001	20241	8.0	8.5
20225678	100001	20241	5.5	6.5
20225736	100001	20241	7.0	7.5
20226216	100001	20241	8.5	9.0
20226547	100001	20241	6.5	7.0
20226741	100001	20241	8.0	8.5
20226783	100001	20241	7.5	8.0
20226789	100001	20241	6.0	6.5
20227635	100001	20241	5.5	6.0
20227636	100001	20241	7.0	7.5
20227654	100001	20241	9.5	10.0
20227689	100001	20241	8.0	8.5
20227823	100001	20241	6.5	7.0
20227890	100001	20241	7.5	8.0
20227891	100001	20241	8.5	9.0
20228734	100001	20241	5.0	5.5
20228865	100001	20241	7.0	7.5
20228891	100001	20241	8.0	8.5
20229123	100001	20241	6.5	7.0
20229378	100001	20241	9.0	9.5
20231245	100001	20241	7.5	8.0
20221025	100001	20241	8.5	9.0
20221026	100001	20241	7.0	7.5
20221256	100001	20241	6.0	6.5
20221278	100001	20241	5.5	6.0
20221465	100001	20241	8.0	8.5
20221493	100001	20241	9.0	9.5
20221976	100001	20241	6.5	7.0
20222167	100001	20241	7.5	8.0
20222367	100001	20241	8.5	9.0
20222540	100001	20241	5.0	6.0
20222541	100001	20241	6.5	7.5
20223219	100001	20241	7.0	8.0
20223451	100001	20241	8.0	8.5
20223589	100001	20241	9.5	10.0
20223641	100001	20241	7.0	7.5
20223945	100001	20241	6.5	7.0
20224075	100001	20241	5.5	6.0
20224076	100001	20241	7.5	8.0
20224390	100001	20241	8.5	9.0
20224489	100001	20241	6.0	6.5
20224589	100001	20241	7.0	7.5
20224657	100001	20241	6.0	6.5
20224734	100001	20241	8.5	9.0
20224735	100001	20241	9.0	9.5
20225467	100001	20241	7.5	8.0
20225482	100001	20241	6.5	7.0
20225674	100001	20241	8.0	8.5
20225735	100001	20241	5.5	6.5
20226215	100001	20241	7.0	7.5
20226531	100001	20241	8.5	9.0
20226734	100001	20241	6.5	7.0
20226791	100001	20241	8.0	8.5
20227634	100001	20241	7.5	8.0
20227812	100001	20241	6.0	6.5
20227856	100001	20241	8.5	9.0
20227892	100001	20241	9.0	9.5
20227893	100001	20241	7.0	7.5
20228311	100001	20241	6.5	7.0
20228312	100001	20241	8.0	8.5
20228791	100001	20241	5.0	5.5
20228872	100001	20241	7.5	8.0
20229102	100001	20241	6.0	6.5
20229103	100001	20241	8.5	9.0
20229145	100001	20241	7.0	7.5
20211234	100001	20232	9.0	9.0
20215555	100001	20241	10.0	2.5
20215556	100001	20241	4.5	6.0
20215557	100001	20241	1.5	7.0
20215558	100001	20241	3.0	4.5
20215559	100001	20241	10.0	0.0
20215560	100001	20241	8.5	0.5
20218888	100001	20241	6.0	10.0
20218889	100001	20241	10.0	7.5
20218890	100001	20241	3.0	9.5
20218891	100001	20241	8.5	10.0
20218892	100001	20241	10.0	1.5
20218893	100001	20241	10.0	9.0
20225555	100001	20241	6.5	6.5
20225556	100001	20241	2.5	6.0
20225557	100001	20241	5.0	7.0
20225558	100001	20241	4.5	3.0
20225559	100001	20241	9.0	2.0
20225560	100001	20241	1.5	10.0
20228888	100001	20241	4.0	10.0
20228889	100001	20241	2.0	9.5
20228890	100001	20241	1.5	9.0
20228892	100001	20241	9.0	10.0
20228893	100001	20241	7.0	8.0
20228899	100001	20241	8.0	4.5
20231226	100001	20241	9.0	9.0
20231230	100001	20241	3.5	7.0
20231231	100001	20241	7.5	7.5
20236578	100001	20241	8.5	1.0
20236756	100001	20241	7.5	0.0
20236766	100001	20241	10.0	9.0
20215555	100002	20241	10.0	2.5
20215556	100002	20241	4.5	6.0
20215557	100002	20241	1.5	7.0
20215558	100002	20241	3.0	4.5
20215559	100002	20241	10.0	0.0
20215560	100002	20241	8.5	0.5
20218888	100002	20241	6.0	10.0
20218889	100002	20241	10.0	7.5
20218890	100002	20241	3.0	9.5
20218891	100002	20241	8.5	10.0
20218892	100002	20241	10.0	1.5
20218893	100002	20241	10.0	9.0
20225555	100002	20241	6.5	6.5
20225556	100002	20241	2.5	6.0
20225557	100002	20241	5.0	7.0
20225558	100002	20241	4.5	3.0
20225559	100002	20241	9.0	2.0
20225560	100002	20241	1.5	10.0
20228888	100002	20241	4.0	10.0
20228889	100002	20241	2.0	9.5
20228890	100002	20241	1.5	9.0
20228892	100002	20241	9.0	10.0
20228893	100002	20241	7.0	8.0
20228899	100002	20241	8.0	4.5
20231226	100002	20241	9.0	9.0
20231230	100002	20241	3.5	7.0
20231231	100002	20241	7.5	7.5
20236578	100002	20241	8.5	1.0
20236756	100002	20241	7.5	0.0
20236766	100002	20241	10.0	9.0
20215555	700001	20241	10.0	2.5
20215556	700001	20241	4.5	6.0
20215557	700001	20241	1.5	7.0
20215558	700001	20241	3.0	4.5
20215559	700001	20241	10.0	0.0
20215560	700001	20241	8.5	0.5
20218888	700001	20241	6.0	10.0
20218889	700001	20241	10.0	7.5
20218890	700001	20241	3.0	9.5
20218891	700001	20241	8.5	10.0
20218892	700001	20241	10.0	1.5
20218893	700001	20241	10.0	9.0
20225555	700001	20241	6.5	6.5
20225556	700001	20241	2.5	6.0
20225557	700001	20241	5.0	7.0
20225558	700001	20241	4.5	3.0
20225559	700001	20241	9.0	2.0
20225560	700001	20241	1.5	10.0
20228888	700001	20241	4.0	10.0
20228889	700001	20241	2.0	9.5
20228890	700001	20241	1.5	9.0
20228892	700001	20241	9.0	10.0
20228893	700001	20241	7.0	8.0
20228899	700001	20241	8.0	4.5
20231226	700001	20241	9.0	9.0
20231230	700001	20241	3.5	7.0
20231231	700001	20241	7.5	7.5
20236578	700001	20241	8.5	1.0
20236756	700001	20241	7.5	0.0
20236766	700001	20241	10.0	9.0
20215555	710001	20241	10.0	2.5
20215556	710001	20241	4.5	6.0
20215557	710001	20241	1.5	7.0
20215558	710001	20241	3.0	4.5
20215559	710001	20241	10.0	0.0
20215560	710001	20241	8.5	0.5
20218888	710001	20241	6.0	10.0
20218889	710001	20241	10.0	7.5
20218890	710001	20241	3.0	9.5
20218891	710001	20241	8.5	10.0
20218892	710001	20241	10.0	1.5
20218893	710001	20241	10.0	9.0
20225555	710001	20241	6.5	6.5
20225556	710001	20241	2.5	6.0
20225557	710001	20241	5.0	7.0
20225558	710001	20241	4.5	3.0
20225559	710001	20241	9.0	2.0
20225560	710001	20241	1.5	10.0
20228888	710001	20241	4.0	10.0
20228889	710001	20241	2.0	9.5
20228890	710001	20241	1.5	9.0
20228892	710001	20241	9.0	10.0
20228893	710001	20241	7.0	8.0
20228899	710001	20241	8.0	4.5
20231226	710001	20241	9.0	9.0
20231230	710001	20241	3.5	7.0
20231231	710001	20241	7.5	7.5
20236578	710001	20241	8.5	1.0
20236756	710001	20241	7.5	0.0
20236766	710001	20241	10.0	9.0
20215555	740001	20241	10.0	2.5
20215556	740001	20241	4.5	6.0
20215557	740001	20241	1.5	7.0
20215558	740001	20241	3.0	4.5
20215559	740001	20241	10.0	0.0
20215560	740001	20241	8.5	0.5
20218888	740001	20241	6.0	10.0
20218889	740001	20241	10.0	7.5
20218890	740001	20241	3.0	9.5
20218891	740001	20241	8.5	10.0
20218892	740001	20241	10.0	1.5
20218893	740001	20241	10.0	9.0
20225555	740001	20241	6.5	6.5
20225556	740001	20241	2.5	6.0
20225557	740001	20241	5.0	7.0
20225558	740001	20241	4.5	3.0
20225559	740001	20241	9.0	2.0
20225560	740001	20241	1.5	10.0
20228888	740001	20241	4.0	10.0
20228889	740001	20241	2.0	9.5
20228890	740001	20241	1.5	9.0
20228892	740001	20241	9.0	10.0
20228893	740001	20241	7.0	8.0
20228899	740001	20241	8.0	4.5
20231226	740001	20241	9.0	9.0
20231230	740001	20241	3.5	7.0
20231231	740001	20241	7.5	7.5
20236578	740001	20241	8.5	1.0
20236756	740001	20241	7.5	0.0
20236766	740001	20241	10.0	9.0
20215555	730001	20241	10.0	2.5
20215556	730001	20241	4.5	6.0
20215557	730001	20241	1.5	7.0
20215558	730001	20241	3.0	4.5
20215559	730001	20241	10.0	0.0
20215560	730001	20241	8.5	0.5
20218888	730001	20241	6.0	10.0
20218889	730001	20241	10.0	7.5
20218890	730001	20241	3.0	9.5
20218891	730001	20241	8.5	10.0
20218892	730001	20241	10.0	1.5
20218893	730001	20241	10.0	9.0
20225555	730001	20241	6.5	6.5
20225556	730001	20241	2.5	6.0
20225557	730001	20241	5.0	7.0
20225558	730001	20241	4.5	3.0
20225559	730001	20241	9.0	2.0
20225560	730001	20241	1.5	10.0
20228888	730001	20241	4.0	10.0
20228889	730001	20241	2.0	9.5
20228890	730001	20241	1.5	9.0
20228892	730001	20241	9.0	10.0
20228893	730001	20241	7.0	8.0
20228899	730001	20241	8.0	4.5
20231226	730001	20241	9.0	9.0
20231230	730001	20241	3.5	7.0
20231231	730001	20241	7.5	7.5
20236578	730001	20241	8.5	1.0
20236756	730001	20241	7.5	0.0
20236766	730001	20241	10.0	9.0
20215555	720001	20241	10.0	2.5
20215556	720001	20241	4.5	6.0
20215557	720001	20241	1.5	7.0
20215558	720001	20241	3.0	4.5
20215559	720001	20241	10.0	0.0
20215560	720001	20241	8.5	0.5
20218888	720001	20241	6.0	10.0
20218889	720001	20241	10.0	7.5
20218890	720001	20241	3.0	9.5
20218891	720001	20241	8.5	10.0
20218892	720001	20241	10.0	1.5
20218893	720001	20241	10.0	9.0
20225555	720001	20241	6.5	6.5
20225556	720001	20241	2.5	6.0
20225557	720001	20241	5.0	7.0
20225558	720001	20241	4.5	3.0
20225559	720001	20241	9.0	2.0
20225560	720001	20241	1.5	10.0
20228888	720001	20241	4.0	10.0
20228889	720001	20241	2.0	9.5
20228890	720001	20241	1.5	9.0
20228892	720001	20241	9.0	10.0
20228893	720001	20241	7.0	8.0
20228899	720001	20241	8.0	4.5
20231226	720001	20241	9.0	9.0
20231230	720001	20241	3.5	7.0
20231231	720001	20241	7.5	7.5
20236578	720001	20241	8.5	1.0
20236756	720001	20241	7.5	0.0
20236766	720001	20241	10.0	9.0
20211234	400001	20241	6.0	6.5
20211234	700001	20241	6.0	6.5
20211234	710001	20241	6.0	6.5
20211234	900003	20241	6.0	6.5
20211234	750001	20241	6.0	6.5
\.


--
-- Data for Name: form_teacher; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.form_teacher (formteacher_id, formteacher_name, gender, phone_number, institute_id, username, pword) FROM stdin;
101002	Trần Thị Hồng Nhung	F	0987654321	FAMI	tranhongnhung101002@ftis.hust.edu.vn	mysecret456
101003	Lê Quốc Khánh	M	0971122334	SEEE	lequockhanh101003@ftis.hust.edu.vn	securepass789
101004	Phạm Thu Trang	F	0934556677	SEM	phamthutrang101004@ftis.hust.edu.vn	passcode101
101005	Bùi Văn Kiên	M	0922233445	FPT	buivankien101005@ftis.hust.edu.vn	letmein2020
101001	Nguyễn Minh Hoàng	M	0912345678	SOICT	nguyenminhhoang101001@ftis.hust.edu.vn	password123
101006	Đào Minh Tuấn	M	0212345678	FAMI	daominhtuan101006@ftis.hust.edu.vn	dragonfire006
101007	Quỳnh Thị Lan	F	0312345678	FED	quynhthilan101007@ftis.hust.edu.vn	buttertiny007
101008	Vũ Quang Hiếu	M	0212345679	FNDSE	vuquanghieu101008@ftis.hust.edu.vn	dragonfire008
101009	Đặng Thị Mai	F	0312345679	FPE	dangthimai101009@ftis.hust.edu.vn	buttertiny009
101010	Nguyễn Minh Kiệt	M	0212345680	FPT	nguyenminhkiet101010@ftis.hust.edu.vn	dragonfire010
101011	Phạm Thị Lan	F	0312345680	SMSE	phamthilan101011@ftis.hust.edu.vn	buttertiny011
101012	Trần Minh Long	M	0212345681	SCLS	tranminhlong101012@ftis.hust.edu.vn	dragonfire012
101013	Vũ Thị Thu	F	0312345681	SEEE	vuthithu101013@ftis.hust.edu.vn	buttertiny013
101014	Quỳnh Minh Hòa	F	0312345682	SEM	quynhminhhoa101014@ftis.hust.edu.vn	buttertiny014
101015	Đào Thanh Sơn	M	0212345682	FEP	daothanhson101015@ftis.hust.edu.vn	dragonfire015
101016	Phạm Minh Hải	M	0212345683	SME	phamminhhai101016@ftis.hust.edu.vn	dragonfire016
101017	Trần Thị Lan	F	0312345683	FOFL	tranthilan101017@ftis.hust.edu.vn	buttertiny017
101018	Vũ Thị Hoài	F	0312345684	SOICT	vuthikhoai101018@ftis.hust.edu.vn	buttertiny018
101019	Đặng Minh Hiếu	M	0212345684	FAMI	dangminhhieu101019@ftis.hust.edu.vn	dragonfire019
101020	Quỳnh Thiên An	F	0312345685	FED	quynhthienan101020@ftis.hust.edu.vn	buttertiny020
101021	Vũ Minh Thu	M	0212345686	FNDSE	vuminhthu101021@ftis.hust.edu.vn	dragonfire021
101022	Nguyễn Quang Sơn	M	0212345687	FPE	nguyenquangson101022@ftis.hust.edu.vn	dragonfire022
101023	Đào Thị Lan	F	0312345688	FPT	daothilan101023@ftis.hust.edu.vn	buttertiny023
101024	Nguyễn Minh Linh	M	0212345689	SMSE	nguyenminhlinh101024@ftis.hust.edu.vn	dragonfire024
101025	Phạm Thị Lan	F	0312345690	SCLS	phamthilan101025@ftis.hust.edu.vn	buttertiny025
101026	Trần Thị Hương	F	0312345691	SEEE	tranthihuong101026@ftis.hust.edu.vn	buttertiny026
101027	Vũ Quang Sơn	M	0212345692	SEM	vuquangson101027@ftis.hust.edu.vn	dragonfire027
101028	Quỳnh Minh Anh	F	0312345693	FEP	quynhminhanh101028@ftis.hust.edu.vn	buttertiny028
101029	Đào Thị Lan	F	0312345694	SME	daothilan101029@ftis.hust.edu.vn	buttertiny029
101030	Phạm Minh Khoa	M	0212345695	FOFL	phamminhkhoa101030@ftis.hust.edu.vn	dragonfire030
101031	Trần Thị Lan	F	0312345696	SOICT	tranthilan101031@ftis.hust.edu.vn	buttertiny031
101032	Vũ Thị Thu	F	0312345697	FAMI	vuthithu101032@ftis.hust.edu.vn	buttertiny032
101033	Đặng Minh Tuấn	M	0212345698	FED	dangminhtuan101033@ftis.hust.edu.vn	dragonfire033
101034	Nguyễn Thị Mai	F	0312345699	FNDSE	nguyenthimai101034@ftis.hust.edu.vn	buttertiny034
101035	Phạm Thị Sơn	F	0312345700	FPE	phamthison101035@ftis.hust.edu.vn	buttertiny035
101036	Trần Minh Lan	M	0212345701	FPT	tranminhlan101036@ftis.hust.edu.vn	dragonfire036
101037	Nguyễn Quang Hòa	M	0212345702	SMSE	nguyenquanghoa101037@ftis.hust.edu.vn	dragonfire037
101038	Vũ Thị Lan	F	0312345703	SCLS	vuthilan101038@ftis.hust.edu.vn	buttertiny038
101039	Nguyễn Minh Đức	M	0212345704	SEEE	nguyenminhduc101039@ftis.hust.edu.vn	dragonfire039
101040	Đặng Thị Hồng	F	0312345705	SEM	dangthihong101040@ftis.hust.edu.vn	buttertiny040
\.


--
-- Data for Name: give_conduct_point; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.give_conduct_point (formteacher_id, student_id, semester_id, conduct_point) FROM stdin;
101002	20226001	20222	\N
101001	20226000	20222	\N
\.


--
-- Data for Name: grade_rule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.grade_rule (alphabet_point, four_scale, ten_scale_from, ten_scale_to) FROM stdin;
A+	4.0	9.5	10.0
A	4.0	8.5	9.4
B+	3.5	8.0	8.4
B	3.0	7.0	7.9
C+	2.5	6.5	6.9
C	2.0	5.5	6.4
D+	1.5	5.0	5.4
D	1.0	4.0	4.9
F	0.0	0.0	3.9
\.


--
-- Data for Name: headmaster; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.headmaster (headmaster_id, institute_id, headmaster_name, gender, phone_number, username, pword) FROM stdin;
1001	FAMI	Nguyễn Thị Mai	F	0123456789	nguyenmaimai1001@his.hust.edu.vn	mypassword1
1002	FED	Trần Văn An	M	0123456790	tranvanan1002@his.hust.edu.vn	mypassword2
1004	SCLS	Phạm Thị Lan	F	0123456792	phamthilan1004@his.hust.edu.vn	mypassword4
1005	SEEE	Hoàng Văn Khánh	M	0123456793	hoangvankhanh1005@his.hust.edu.vn	mypassword5
1006	SEM	Đặng Thị Bích	F	0123456794	dangthibich1006@his.hust.edu.vn	mypassword6
1008	SME	Ngô Thị Lan Anh	F	0123456796	ngothilananh1008@his.hust.edu.vn	mypassword8
1011	FPE	Nguyễn Quang Huy	M	0123456799	nguyenquanghuy1011@his.hust.edu.vn	mypassword11
1012	FPT	Lê Phương Uyên	F	0123456800	lephuonguyen1012@his.hust.edu.vn	mypassword12
1013	FNDSE	Trương Thị Kim Chi	F	0123456801	truongthikimchi1013@his.hust.edu.vn	mypassword13
1003	SMSE	Lê Minh Tuấn	M	0123456791	leminhtuan1003@his.hust.edu.vn	mypassword3
1007	FEP	Vũ Minh Hiếu	M	0123456795	vuminhieu1007@his.hust.edu.vn	mypassword7
1010	SOICT	Vũ Hoàng Duy	M	0123456798	vuhoangduy1010@his.hust.edu.vn	mypassword10
1009	FOFL	Bùi Minh Tuệ	F	0123456797	buiminhtue1009@his.hust.edu.vn	mypassword9
\.


--
-- Data for Name: institute; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.institute (institute_id, institute_name, address) FROM stdin;
FOFL	Faculty of Foreign Languages	Phòng M312 - Tòa nhà C7 - Số 1 Đại Cồ Việt - Hai Bà Trưng - Hà Nội
SCLS	School of Chemistry and Life Sciences	Phòng 202 - Tòa nhà C4 - số 1 Đại Cồ Việt - Hai Bà Trưng - Hà Nội
SEM	School of Economics and Management	Đại Cồ Việt - Hai Bà Trưng - Hà Nội
SEEE	School of Electrical and Electronic Engineering	Phòng E.605 - Tầng 6 - Tòa nhà C7 - Số 1 Đại Cồ Việt - Hai Bà Trưng - Hà Nội
SME	School of Mechanical Engineering	Phòng 614 - Tòa nhà C7 - Số 1 Đại Cồ Việt - Hai Bà Trưng - Hà Nội
FNDSE	Faculty of National Defense – Security Education	\N
FPE	Faculty of Physical Education	\N
FPT	Faculty of Political Theory	\N
FED	Faculty of Engineering Pedagogy	Phòng M321 - Tòa nhà C7 -  Đại học Bách Khoa Hà Nội
SMSE	School of Materials Science and Engineering	Phòng 314 /315 - Tòa nhà C5 - Số 1 Đại Cồ Việt - Hai Bà Trưng - Hà Nội
FEP	Faculty of Engineering Physics	Phòng  116 - Tòa nhà C10 - Số 1 Đại Cồ Việt - Hai Bà Trưng - Hà Nội
SOICT	School of Information and Communication Technology	Phòng 505 - Tòa nhà B1 - Số 1 Đại Cồ Việt - Hai Bà Trưng - Hà Nội
FAMI	Faculty of Applied Mathematics and Informatics	Phòng 106 - Tòa nhà D3 - số 1 Đại Cồ Việt - Hai Bà Trưng - Hà Nội
\.


--
-- Data for Name: lecturer; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lecturer (lecturer_id, lecturer_name, gender, phone_number, institute_id, username, pword) FROM stdin;
100202	Trần Thị Hồng Mai	F	0987654321	FAMI	tranthihongmai100202@lis.hust.edu.vn	mysecret456
100203	Lê Quang Hieu	M	0971122334	FED	lequanghieu100203@lis.hust.edu.vn	securepass789
100204	Phạm Thị Thu Trang	F	0934556677	SEM	phamthithutrang100204@lis.hust.edu.vn	passcode101
100205	Bùi Văn Kiên	M	0922233445	SEEE	buivankien100205@lis.hust.edu.vn	letmein2020
100207	Nguyễn Thị Lan	F	0944455666	SCLS	nguyenthilan100207@lis.hust.edu.vn	1234abcd
100208	Lê Văn Quang	M	0973322110	FNDSE	levanquang100208@lis.hust.edu.vn	welcome123
100209	Phan Thi Mai	F	0911223344	FPT	phanthimai100209@lis.hust.edu.vn	12345xyz
100211	\N	\N	\N	FED	\N	\N
100210	Hoàng Thị Hồng	F	0922334455	SMSE	hoangthihong100210@lis.hust.edu.vn	securepass01
100201	Nguyễn Minh Tuấn	M	0912345678	SOICT	nguyenminhtuan100201@lis.hust.edu.vn	password123
100206	Đặng Thanh Sơn	M	0910987654	SOICT	dangthanhnson100206@lis.hust.edu.vn	adminpassword
101006	Đào Minh Tuấn	M	0212345678	FAMI	daominhtuan101006@ftis.hust.edu.vn	dragonfire006
101007	Quỳnh Thị Lan	F	0312345678	FED	quynhthilan101007@ftis.hust.edu.vn	buttertiny007
101008	Vũ Quang Hiếu	M	0212345679	FNDSE	vuquanghieu101008@ftis.hust.edu.vn	dragonfire008
101009	Đặng Thị Mai	F	0312345679	FPE	dangthimai101009@ftis.hust.edu.vn	buttertiny009
101010	Nguyễn Minh Kiệt	M	0212345680	FPT	nguyenminhkiet101010@ftis.hust.edu.vn	dragonfire010
101011	Phạm Thị Lan	F	0312345680	SMSE	phamthilan101011@ftis.hust.edu.vn	buttertiny011
101012	Trần Minh Long	M	0212345681	SCLS	tranminhlong101012@ftis.hust.edu.vn	dragonfire012
101013	Vũ Thị Thu	F	0312345681	SEEE	vuthithu101013@ftis.hust.edu.vn	buttertiny013
101014	Quỳnh Minh Hòa	F	0312345682	SEM	quynhminhhoa101014@ftis.hust.edu.vn	buttertiny014
101015	Đào Thanh Sơn	M	0212345682	FEP	daothanhson101015@ftis.hust.edu.vn	dragonfire015
101016	Phạm Minh Hải	M	0212345683	SME	phamminhhai101016@ftis.hust.edu.vn	dragonfire016
101017	Trần Thị Lan	F	0312345683	FOFL	tranthilan101017@ftis.hust.edu.vn	buttertiny017
101018	Vũ Thị Hoài	F	0312345684	SOICT	vuthikhoai101018@ftis.hust.edu.vn	buttertiny018
101019	Đặng Minh Hiếu	M	0212345684	FAMI	dangminhhieu101019@ftis.hust.edu.vn	dragonfire019
101020	Quỳnh Thiên An	F	0312345685	FED	quynhthienan101020@ftis.hust.edu.vn	buttertiny020
101021	Vũ Minh Thu	M	0212345686	FNDSE	vuminhthu101021@ftis.hust.edu.vn	dragonfire021
101022	Nguyễn Quang Sơn	M	0212345687	FPE	nguyenquangson101022@ftis.hust.edu.vn	dragonfire022
101023	Đào Thị Lan	F	0312345688	FPT	daothilan101023@ftis.hust.edu.vn	buttertiny023
101024	Nguyễn Minh Linh	M	0212345689	SMSE	nguyenminhlinh101024@ftis.hust.edu.vn	dragonfire024
101025	Phạm Thị Lan	F	0312345690	SCLS	phamthilan101025@ftis.hust.edu.vn	buttertiny025
101026	Trần Thị Hương	F	0312345691	SEEE	tranthihuong101026@ftis.hust.edu.vn	buttertiny026
101027	Vũ Quang Sơn	M	0212345692	SEM	vuquangson101027@ftis.hust.edu.vn	dragonfire027
101028	Quỳnh Minh Anh	F	0312345693	FEP	quynhminhanh101028@ftis.hust.edu.vn	buttertiny028
101029	Đào Thị Lan	F	0312345694	SME	daothilan101029@ftis.hust.edu.vn	buttertiny029
101030	Phạm Minh Khoa	M	0212345695	FOFL	phamminhkhoa101030@ftis.hust.edu.vn	dragonfire030
101031	Trần Thị Lan	F	0312345696	SOICT	tranthilan101031@ftis.hust.edu.vn	buttertiny031
101032	Vũ Thị Thu	F	0312345697	FAMI	vuthithu101032@ftis.hust.edu.vn	buttertiny032
101033	Đặng Minh Tuấn	M	0212345698	FED	dangminhtuan101033@ftis.hust.edu.vn	dragonfire033
101034	Nguyễn Thị Mai	F	0312345699	FNDSE	nguyenthimai101034@ftis.hust.edu.vn	buttertiny034
101035	Phạm Thị Sơn	F	0312345700	FPE	phamthison101035@ftis.hust.edu.vn	buttertiny035
101036	Trần Minh Lan	M	0212345701	FPT	tranminhlan101036@ftis.hust.edu.vn	dragonfire036
101037	Nguyễn Quang Hòa	M	0212345702	SMSE	nguyenquanghoa101037@ftis.hust.edu.vn	dragonfire037
101038	Vũ Thị Lan	F	0312345703	SCLS	vuthilan101038@ftis.hust.edu.vn	buttertiny038
101039	Nguyễn Minh Đức	M	0212345704	SEEE	nguyenminhduc101039@ftis.hust.edu.vn	dragonfire039
101040	Đặng Thị Hồng	F	0312345705	SEM	dangthihong101040@ftis.hust.edu.vn	buttertiny040
100006	Lê Minh Đức	M	0212345706	FAMI	leminhduc100006@ftis.hust.edu.vn	dragonfire006
100007	Hoàng Thị Lan	F	0312345707	FED	hoangthilan100007@ftis.hust.edu.vn	buttertiny007
100008	Nguyễn Quang Duy	M	0212345708	FNDSE	nguyenquangduy100008@ftis.hust.edu.vn	dragonfire008
100009	Vũ Minh Thu	M	0212345709	FPE	vuminhthu100009@ftis.hust.edu.vn	dragonfire009
100010	Đặng Thị Mai	F	0312345710	FPT	dangthimai100010@ftis.hust.edu.vn	buttertiny010
100011	Phạm Minh Hòa	M	0212345711	SMSE	phamminhhoa100011@ftis.hust.edu.vn	dragonfire011
100012	Trần Minh Ánh	M	0212345712	SCLS	tranminhanh100012@ftis.hust.edu.vn	dragonfire012
100013	Nguyễn Quang Sơn	M	0212345713	SEEE	nguyenquangson100013@ftis.hust.edu.vn	dragonfire013
100014	Vũ Minh Hương	F	0312345714	SEM	vuminhhuong100014@ftis.hust.edu.vn	buttertiny014
100015	Quỳnh Thị Hương	F	0312345715	FEP	quynhthihuong100015@ftis.hust.edu.vn	buttertiny015
100016	Đào Minh Lâm	M	0212345716	SME	daominhlam100016@ftis.hust.edu.vn	dragonfire016
100017	Phạm Minh Khoa	M	0212345717	FOFL	phamminhkhoa100017@ftis.hust.edu.vn	dragonfire017
100018	Trần Thị Thu	F	0312345718	SOICT	tranthithu100018@ftis.hust.edu.vn	buttertiny018
100019	Nguyễn Minh An	M	0212345719	FAMI	nguyenminhan100019@ftis.hust.edu.vn	dragonfire019
100020	Vũ Thị Thương	F	0312345720	FED	vuthithuong100020@ftis.hust.edu.vn	buttertiny020
100021	Đặng Minh Quân	M	0212345721	FNDSE	dangminhquan100021@ftis.hust.edu.vn	dragonfire021
100022	Nguyễn Thị Lan	F	0312345722	FPE	nguyenthilan100022@ftis.hust.edu.vn	buttertiny022
100023	Trần Minh Tuyết	M	0212345723	FPT	tranminhtuyet100023@ftis.hust.edu.vn	dragonfire023
100024	Vũ Minh Hà	M	0212345724	SMSE	vuminhha100024@ftis.hust.edu.vn	dragonfire024
100025	Hoàng Thị Hoài	F	0312345725	SCLS	hoangthikhoai100025@ftis.hust.edu.vn	buttertiny025
\.


--
-- Data for Name: semester; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.semester (semester_id, start_enroll_time, finish_enroll_time, start_givepoint_time, finish_givepoint_time, start_semester_date, finish_semester_date) FROM stdin;
20221	2022-08-01 14:00:00	2022-08-15 14:00:00	2023-01-27 00:00:00	2023-02-10 00:00:00	2022-01-01	2022-06-01
20222	2023-01-01 14:00:00	2023-01-15 14:00:00	2023-07-01 00:00:00	2023-07-15 00:00:00	2022-06-01	2023-01-01
20231	2023-08-01 14:00:00	2023-08-15 14:00:00	2024-01-27 00:00:00	2024-02-10 00:00:00	2023-01-01	2023-06-01
20232	2024-01-01 14:00:00	2024-01-15 14:00:00	2024-07-01 00:00:00	2024-07-15 00:00:00	2023-06-01	2024-01-01
20241	2024-08-01 14:00:00	2024-08-15 14:00:00	2025-01-27 00:00:00	2025-02-10 00:00:00	2024-01-01	2024-06-01
20242	2025-01-01 14:00:00	2025-01-15 14:00:00	2025-07-01 00:00:00	2025-07-15 00:00:00	2024-06-01	2025-01-01
20212	2022-01-01 14:00:00	2022-01-15 14:00:00	2022-07-01 00:00:00	2022-07-15 00:00:00	2021-06-01	2022-01-01
20211	2021-08-01 14:00:00	2021-08-15 14:00:00	2022-01-27 00:00:00	2022-02-10 00:00:00	2021-01-01	2021-06-01
\.


--
-- Data for Name: student; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student (student_id, citizen_id, student_name, gender, dob, major, institute_id, username, pword) FROM stdin;
20231247	001234567818	Trần Thị Ngọc	F	2004-04-24	MI2	FAMI	ngoc.tt1247	24042004
20236578	001234567819	Lê Văn Kiên	M	2004-06-06	EE1	SEEE	kien.lv6578	06062004
20237891	001234567820	Ngô Thị Quỳnh	F	2004-08-18	EE2	SEEE	quynh.nt7891	18082004
20239854	001234567821	Hoàng Văn Sơn	M	2004-10-12	FL1	FOFL	son.hv9854	12102004
20238965	001234567822	Phạm Thị Hồng	F	2004-12-22	FL2	FOFL	hong.pt8965	22122004
20231234	001234567823	Trần Văn Thái	M	2004-02-15	MI1	FAMI	thai.tv1234	15022004
20237890	001234567824	Lê Thị Lý	F	2004-04-27	MI2	FAMI	ly.lt7890	27042004
20236756	001234567825	Ngô Văn Lâm	M	2004-06-03	EE1	SEEE	lam.nv6756	03062004
20238921	001234567826	Nguyễn Thị Hoa	F	2004-08-07	EE2	SEEE	hoa.nt8921	07082004
20231241	001234567827	Hoàng Văn Tuấn	M	2004-10-19	FL1	FOFL	tuan.hv1241	19102004
20235478	001234567828	Phạm Thị Tuyết	F	2004-12-01	FL2	FOFL	tuyet.pt5478	01122004
20239988	001234567829	Trần Văn Khang	M	2004-02-22	MI1	FAMI	khang.tv9988	22022004
20238999	001234567830	Ngô Thị Thanh	F	2004-04-30	MI2	FAMI	thanh.nt8999	30042004
20231226	001234567831	Lê Văn An	M	2004-06-20	EE1	SEEE	an.lv1226	20062004
20237778	001234567832	Hoàng Thị Hiền	F	2004-08-11	EE2	SEEE	hien.ht7778	11082004
20239889	001234567833	Phạm Văn Phúc	M	2004-10-17	FL1	FOFL	phuc.pv9889	17102004
20235455	001234567834	Trần Thị Lan	F	2004-12-26	FL2	FOFL	lan.tt5455	26122004
20231221	001234567835	Ngô Văn Vinh	M	2004-02-14	MI1	FAMI	vinh.nv1221	14022004
20238988	001234567836	Nguyễn Thị Đào	F	2004-04-18	MI2	FAMI	dao.nt8988	18042004
20236766	001234567837	Hoàng Văn Bình	M	2004-06-25	EE1	SEEE	binh.hv6766	25062004
20235454	001234567838	Phạm Thị Hà	F	2004-08-28	EE2	SEEE	ha.pt5454	28082004
20239999	001234567839	Trần Văn Hưng	M	2004-10-22	FL1	FOFL	hung.tv9999	22102004
20226001	123412341234	ghy	\N	\N	\N	FAMI	\N	\N
20226000	123412341234	ghy	\N	\N	\N	SOICT	\N	\N
20231245	001234567891	Trần Minh Tuấn	M	2003-02-02	IT2	SOICT	tuan.tm1245	02022003
20241256	001234567892	Lê Thị Bích Ngọc	F	2005-03-15	IT1	SOICT	ngoc.lt1256	15032005
20221278	001234567893	Phạm Minh Tân	M	2004-04-25	ITe7	SOICT	tan.pm1278	25042004
20211234	001234567894	Ngô Thị Thanh Hà	F	2002-06-06	IT2	SOICT	ha.nt1234	06062002
20231389	001234567895	Bùi Anh Khoa	M	2003-07-20	IT1	SOICT	khoa.ba1389	20072003
20226215	001234567866	Nguyễn Minh Tâm	M	2004-04-07	ITe7	SOICT	tam.nm6215	70404002
20227892	001234567862	Trần Hoài An	M	2004-05-03	ITe7	SOICT	an.th7892	30504002
20227635	001234567826	Lê Minh Phong	M	2004-12-14	IT2	SOICT	phong.lm7635	41214002
20229102	001234567881	Trần Minh An	M	2004-01-19	ITe7	SOICT	an.tm9102	91104002
20222540	001234567809	Nguyễn Thanh Hương	M	2004-10-27	ITe7	SOICT	huong.nt2540	72014002
20225735	001234567896	Lê Thị Thanh Hương	F	2004-04-14	ITe7	SOICT	huong.lt5735	41404002
20224075	001234567897	Nguyễn Thanh Hải	F	2004-11-13	ITe7	SOICT	hai.nt4075	31114002
20224734	001234567877	Trần Thanh Bảo	F	2004-01-28	ITe7	SOICT	bao.tt4734	82104002
20223080	001234567846	Nguyễn Thị Lan	M	2004-05-05	IT2	SOICT	lan.nt3080	50504002
20228311	001234567885	Đặng Bích Anh	M	2004-06-11	ITe7	SOICT	anh.db8311	11604002
20226216	001234567811	Nguyễn Thị Lan Anh	F	2004-03-20	IT2	SOICT	lan.nt6216	20030302
20227893	001234567821	Trần Bảo Lâm	M	2004-07-11	ITe7	SOICT	lam.tb7893	11072004
20227636	001234567832	Lê Quang Tú	M	2004-11-05	IT2	SOICT	tu.lq7636	05112004
20229103	001234567882	Phạm Quỳnh Trang	F	2004-08-16	ITe7	SOICT	trang.pqt9103	16082004
20222541	001234567810	Trương Minh Thiện	M	2004-09-22	ITe7	SOICT	thien.tm2541	22092004
20225736	001234567897	Nguyễn Phúc Lâm	M	2004-05-02	IT2	SOICT	lam.npl5736	02052004
20224076	001234567898	Bùi Hồng Ánh	F	2004-06-19	ITe7	SOICT	anh.bha4076	19062004
20224735	001234567878	Đoàn Minh Hiếu	M	2004-12-30	ITe7	SOICT	hieu.dm4735	30122004
20223081	001234567847	Nguyễn Phương Lý	F	2004-10-03	IT2	SOICT	ly.npl3081	03102004
20228312	001234567886	Lâm Thị Thanh Hằng	F	2004-06-25	ITe7	SOICT	hang.lt8312	25062004
20221026	001234567861	Trần Minh Trí	M	2004-03-14	ITe7	SOICT	tri.tm1026	14032004
20221025	001234567860	Nguyễn Thanh Quang	F	2004-06-06	ITe7	SOICT	quang.nt1025	60604002
20231230	001234567801	Nguyễn Văn Hùng	M	2004-03-14	EE1	SEEE	hung.nv1230	14032004
20235678	001234567802	Trần Thị Nhung	F	2004-05-22	EE2	SEEE	nhung.tt5678	22052004
20239877	001234567803	Lê Văn An	M	2004-07-16	EE1	SEEE	an.lv9877	16072004
20231249	001234567804	Hoàng Thị Bích	F	2004-09-08	EE2	SEEE	bich.ht1249	08092004
20235432	001234567805	Phạm Văn Cường	M	2004-01-11	FL1	FOFL	cuong.pv5432	11012004
20234567	001234567806	Ngô Thị Hằng	F	2004-03-25	FL2	FOFL	hang.nt4567	25032004
20237899	001234567807	Vũ Văn Phong	M	2004-06-04	FL1	FOFL	phong.vv7899	04062004
20239855	001234567808	Trần Thị Lan	F	2004-08-20	FL2	FOFL	lan.tt9855	20082004
20236789	001234567809	Nguyễn Văn Thành	M	2004-10-10	MI1	FAMI	thanh.nv6789	10102004
20231246	001234567810	Hoàng Thị Mai	F	2004-12-18	MI2	FAMI	mai.ht1246	18122004
20237654	001234567811	Phạm Văn Nam	M	2004-02-27	MI1	FAMI	nam.pv7654	27022004
20238901	001234567812	Trần Thị Phúc	F	2004-04-15	MI2	FAMI	phuc.tt8901	15042004
20231231	001234567813	Lê Văn Khánh	M	2004-06-11	EE1	SEEE	khanh.lv1231	11062004
20236587	001234567814	Ngô Thị Dung	F	2004-08-09	EE2	SEEE	dung.nt6587	09082004
20237892	001234567815	Hoàng Văn Minh	M	2004-10-03	FL1	FOFL	minh.hv7892	03102004
20239876	001234567816	Phạm Thị Yến	F	2004-12-29	FL2	FOFL	yen.pt9876	29122004
20238912	001234567817	Nguyễn Văn Duy	M	2004-02-19	MI1	FAMI	duy.nv8912	19022004
20224612	001234567852	Nguyễn Văn Hào	M	2004-03-15	IT2	SOICT	hao.nv4612	15032004
20228734	001234567867	Trần Thị Bích	F	2004-08-23	IT2	SOICT	bich.tt8734	23082004
20225431	001234567899	Lê Hoàng Cường	M	2004-05-12	IT2	SOICT	cuong.lh5431	12052004
20229378	001234567832	Phạm Thị Dung	F	2004-12-30	IT2	SOICT	dung.pt9378	30122004
20221987	001234567845	Hoàng Văn Đông	M	2004-07-14	IT2	SOICT	dong.hv1987	14072004
20227654	001234567878	Ngô Thị Phương	F	2004-09-06	IT2	SOICT	phuong.nt7654	06092004
20221468	001234567812	Vũ Đức Lâm	M	2004-02-25	IT2	SOICT	lam.vd1468	25022004
20224321	001234567889	Đặng Thị Huệ	F	2004-11-11	IT2	SOICT	hue.dt4321	11112004
20227890	001234567833	Nguyễn Thành An	M	2004-06-18	IT2	SOICT	an.nt7890	18062004
20223987	001234567866	Trần Văn Khải	M	2004-04-07	IT2	SOICT	khai.tv3987	07042004
20228891	001234567844	Lê Thị Liên	F	2004-10-02	IT2	SOICT	lien.lt8891	02102004
20226547	001234567833	Hoàng Văn Minh	M	2004-03-27	IT2	SOICT	minh.hv6547	27032004
20222134	001234567855	Phạm Văn Nam	M	2004-01-19	IT2	SOICT	nam.pv2134	19012004
20224456	001234567877	Đỗ Thị Oanh	F	2004-05-05	IT2	SOICT	oanh.dt4456	05052004
20227823	001234567866	Nguyễn Hoàng Phúc	M	2004-09-10	IT2	SOICT	phuc.nh7823	10092004
20225432	001234567812	Lê Thị Quỳnh	F	2004-02-14	IT2	SOICT	quynh.lt5432	14022004
20221234	001234567844	Vũ Văn Duy	M	2004-04-25	IT2	SOICT	duy.vv1234	25042004
20223210	001234567811	Trần Văn Sơn	M	2004-06-13	IT2	SOICT	son.tv3210	13062004
20224567	001234567888	Ngô Thị Tâm	F	2004-07-22	IT2	SOICT	tam.nt4567	22072004
20226783	001234567855	Đặng Văn Hùng	M	2004-08-29	IT2	SOICT	hung.dv6783	29082004
20223645	001234567877	Hoàng Văn Vinh	M	2004-10-17	IT2	SOICT	vinh.hv3645	17102004
20229123	001234567822	Nguyễn Văn Tuấn	M	2004-01-06	IT2	SOICT	tuan.nv9123	06012004
20221245	001234567877	Trần Thị Xuân	F	2004-03-30	IT2	SOICT	xuan.tt1245	30032004
20222345	001234567899	Phạm Thị Yến	F	2004-12-18	IT2	SOICT	yen.pt2345	18122004
20225678	001234567811	Lê Hoàng Khánh	M	2004-05-22	IT2	SOICT	khanh.lh5678	22052004
20224521	001234567844	Ngô Văn Kiên	M	2004-07-04	IT2	SOICT	kien.nv4521	04072004
20223456	001234567899	Vũ Đức Tùng	M	2004-09-15	IT2	SOICT	tung.vd3456	15092004
20226741	001234567855	Đặng Thị Linh	F	2004-10-21	IT2	SOICT	linh.dt6741	21102004
20225478	001234567888	Nguyễn Văn Bảo	M	2004-11-05	IT2	SOICT	bao.nv5478	05112004
20221489	001234567811	Hoàng Văn Cảnh	M	2004-01-25	IT2	SOICT	canh.hv1489	25012004
20223567	001234567833	Trần Thị Phúc	F	2004-02-13	IT2	SOICT	phuc.tt3567	13022004
20227689	001234567866	Phạm Văn Hiếu	M	2004-04-10	IT2	SOICT	hieu.pv7689	10042004
20227891	001234567832	Đỗ Văn Khôi	M	2004-05-28	IT2	SOICT	khoi.dv7891	28052004
20221452	001234567822	Nguyễn Thị Ngọc	F	2004-06-19	IT2	SOICT	ngoc.nt1452	19062004
20228865	001234567855	Lê Hoàng Hà	M	2004-07-31	IT2	SOICT	ha.lh8865	31072004
20221243	001234567877	Trần Văn Thành	M	2004-08-12	IT2	SOICT	thanh.tv1243	12082004
20224356	001234567811	Ngô Thị Hồng	F	2004-09-27	IT2	SOICT	hong.nt4356	27092004
20226789	001234567833	Đặng Văn Quang	M	2004-10-06	IT2	SOICT	quang.dv6789	06102004
20221231	001234567811	Hoàng Văn Lộc	M	2004-12-08	IT2	SOICT	loc.hv1231	08132004
20223333	034987654321	Đào Minh Hoàn	M	2004-03-15	FL1	FOFL	hoan.dm3333	15032004
20224444	034987654322	Trần Ngọc Khiêm	M	2004-05-18	MI2	FAMI	khiem.tn4444	18052004
20225555	034987654323	Dĩ Quang Đại	M	2003-11-02	EE1	SEEE	dai.dq5555	02112003
20226666	034987654324	Hoàn Thị Diễm	F	2004-07-23	FL1	FOFL	diem.ht6666	23072004
20227777	034987654325	Diễm Thanh Tố	F	2004-09-12	MI2	FAMI	to.dt7777	12092004
20228888	034987654326	Hồ Văn Đại	M	2004-04-14	EE1	SEEE	dai.hv8888	14042004
20223334	034987654327	Tạ Đức Khiêm	M	2004-08-29	FL1	FOFL	khiem.td3334	29082004
20224445	034987654328	Phan Minh Quách	M	2003-06-07	MI2	FAMI	quach.pm4445	07062003
20225556	034987654329	Trương Thị Tố	F	2004-01-10	EE1	SEEE	to.tt5556	10012004
20226667	034987654330	Đoàn Hoàng Cồ	M	2004-12-25	FL1	FOFL	co.dh6667	25122004
20227778	034987654331	Lã Thị Diễm	F	2004-03-03	MI2	FAMI	diem.lt7778	03032004
20228889	034987654332	Khiêm Văn Hoàn	M	2004-09-19	EE1	SEEE	hoan.kv8889	19092004
20223335	034987654333	Quách Thị Đào	F	2004-07-08	FL1	FOFL	dao.qt3335	08072004
20224446	034987654334	Tố Minh Trần	M	2004-10-11	MI2	FAMI	tran.tm4446	11102004
20225557	034987654335	Vũ Hoàng Lã	M	2004-06-18	EE1	SEEE	la.vh5557	18062004
20226668	034987654336	Đại Thị Diễm	F	2004-04-16	FL1	FOFL	diem.dt6668	16042004
20227779	034987654337	Cồ Văn Đại	M	2004-11-21	MI2	FAMI	dai.cv7779	21112004
20228890	034987654338	Đoàn Thanh Đào	F	2004-02-12	EE1	SEEE	dao.dt8890	12022004
20223336	034987654339	Hồ Ngọc Tố	F	2003-12-30	FL1	FOFL	to.hn3336	30122003
20224447	034987654340	Lã Hoàng Trần	M	2004-01-04	MI2	FAMI	tran.lh4447	04012004
20225558	034987654341	Quách Văn Quang	M	2004-08-08	EE1	SEEE	quang.qv5558	08082004
20226669	034987654342	Phan Thị Khiêm	F	2004-09-03	FL1	FOFL	khiem.pt6669	03092004
20227780	034987654343	Đào Minh Phan	M	2004-05-05	MI2	FAMI	phan.dm7780	05052004
20228899	034987654344	Diễm Văn Lã	M	2003-04-18	EE1	SEEE	la.dv8899	18042003
20223337	034987654345	Đoàn Thanh Tố	F	2004-03-25	FL1	FOFL	to.dt3337	25032004
20224448	034987654346	Đại Đức Trần	M	2004-12-09	MI2	FAMI	tran.dd4448	09122004
20225559	034987654347	Lã Ngọc Đại	M	2004-10-27	EE1	SEEE	dai.ln5559	27102004
20226670	034987654348	Phan Hoàng Khiêm	M	2004-11-11	FL1	FOFL	khiem.ph6670	11112004
20227781	034987654349	Tố Văn Diễm	F	2004-06-02	MI2	FAMI	diem.tv7781	02062004
20228892	034987654350	Trương Thị Đào	F	2004-07-15	EE1	SEEE	dao.tt8892	15072004
20223338	034987654351	Quách Ngọc Trần	M	2004-08-22	FL1	FOFL	tran.qn3338	22082004
20224449	034987654352	Cồ Văn Đại	M	2003-09-10	MI2	FAMI	dai.cv4449	10092003
20225560	034987654353	Hồ Thị Lã	F	2004-05-18	EE1	SEEE	la.ht5560	18052004
20226671	034987654354	Đào Minh Khiêm	M	2004-03-29	FL1	FOFL	khiem.dm6671	29032004
20227782	034987654355	Đại Thị Tố	F	2004-04-03	MI2	FAMI	to.dt7782	03042004
20228893	034987654356	Phan Văn Quách	M	2004-08-04	EE1	SEEE	quach.pv8893	04082004
20223339	034987654357	Trần Ngọc Diễm	F	2004-09-17	FL1	FOFL	diem.tn3339	17092004
20224450	034987654358	Vũ Đức Khiêm	M	2004-10-25	MI2	FAMI	khiem.vd4450	25102004
20213333	025203782341	Đào Văn Đại	M	2003-03-12	FL1	FOFL	dai.dv3333	12032003
20214444	025203782342	Trần Thị Khiêm	F	2003-07-15	MI2	FAMI	khiem.tt4444	15072003
20215555	025203782343	Dĩ Minh Hoàn	M	2003-10-09	EE1	SEEE	hoan.dm5555	09102003
20216666	025203782344	Hoàn Thị Tố	F	2003-04-18	FL1	FOFL	to.ht6666	18042003
20217777	025203782345	Diễm Quang Khiêm	M	2003-06-22	MI2	FAMI	khiem.dq7777	22062003
20218888	025203782346	Hồ Văn Phan	M	2003-09-19	EE1	SEEE	phan.hv8888	19092003
20213334	025203782347	Tạ Đức Đại	M	2003-08-25	FL1	FOFL	dai.td3334	25082003
20214445	025203782348	Phan Thanh Quách	M	2003-03-17	MI2	FAMI	quach.pt4445	17032003
20215556	025203782349	Trương Thị Cồ	F	2003-05-10	EE1	SEEE	co.tt5556	10052003
20216667	025203782350	Đoàn Hoàng Đại	M	2003-12-01	FL1	FOFL	dai.dh6667	01122003
20217778	025203782351	Lã Thị Tố	F	2003-07-30	MI2	FAMI	to.lt7778	30072003
20218889	025203782352	Khiêm Văn Đại	M	2003-11-22	EE1	SEEE	dai.kv8889	22112003
20213335	025203782353	Quách Ngọc Hoàn	M	2003-04-14	FL1	FOFL	hoan.qn3335	14042003
20214446	025203782354	Tố Minh Lã	M	2003-10-02	MI2	FAMI	la.tm4446	02102003
20215557	025203782355	Vũ Đức Tố	M	2003-06-05	EE1	SEEE	to.vd5557	05062003
20216668	025203782356	Đại Thị Diễm	F	2003-08-29	FL1	FOFL	diem.dt6668	29082003
20217779	025203782357	Cồ Ngọc Phan	M	2003-03-25	MI2	FAMI	phan.cn7779	25032003
20224657	001234567812	Nguyễn Thị Anh	F	2004-01-15	ITe7	SOICT	anh.nt4657	15012004
20228791	001234567855	Trần Văn Bình	M	2004-03-21	ITe7	SOICT	binh.tv8791	21032004
20225674	001234567833	Lê Thị Chi	F	2004-06-12	ITe7	SOICT	chi.lt5674	12062004
20229145	001234567866	Phạm Văn Đức	M	2004-07-19	ITe7	SOICT	duc.pv9145	19072004
20221976	001234567877	Hoàng Thị Dung	F	2004-09-04	ITe7	SOICT	dung.ht1976	04092004
20221493	001234567844	Vũ Đức Hòa	M	2004-12-03	ITe7	SOICT	hoa.vd1493	03122004
20224390	001234567811	Đặng Thị Hoa	F	2004-02-18	ITe7	SOICT	hoa.dt4390	18022004
20227856	001234567899	Nguyễn Văn Hải	M	2004-05-23	ITe7	SOICT	hai.nv7856	23052004
20223945	001234567888	Trần Thị Lan	F	2004-06-15	ITe7	SOICT	lan.tt3945	15062004
20228872	001234567822	Lê Văn Long	M	2004-07-25	ITe7	SOICT	long.lv8872	25072004
20226531	001234567833	Hoàng Văn Minh	M	2004-03-14	ITe7	SOICT	minh.hv6531	14032004
20222167	001234567855	Phạm Thị Nga	F	2004-01-10	ITe7	SOICT	nga.pt2167	10012004
20224489	001234567866	Đỗ Văn Nam	M	2004-04-07	ITe7	SOICT	nam.dv4489	07042004
20227812	001234567822	Nguyễn Thị Oanh	F	2004-05-19	ITe7	SOICT	oanh.nt7812	19052004
20225467	001234567811	Lê Văn Phong	M	2004-08-02	ITe7	SOICT	phong.lv5467	02082004
20221256	001234567833	Trần Văn Quyết	M	2004-06-18	ITe7	SOICT	quyet.tv1256	18062004
20223219	001234567855	Nguyễn Thị Sen	F	2004-07-31	ITe7	SOICT	sen.nt3219	31072004
20226734	001234567877	Hoàng Văn Tài	M	2004-09-26	ITe7	SOICT	tai.hv6734	26092004
20223641	001234567822	Nguyễn Thị Thanh	F	2004-10-14	ITe7	SOICT	thanh.nt3641	14102004
20222367	001234567899	Phạm Văn Trường	M	2004-04-16	ITe7	SOICT	truong.pv2367	16042004
20218890	025203782358	Đoàn Văn Lã	M	2003-02-07	EE1	SEEE	la.dv8890	07022003
20224589	001234567877	Ngô Văn Việt	M	2004-07-08	ITe7	SOICT	viet.nv4589	08072004
20223451	001234567866	Vũ Thị Xuân	F	2004-09-12	ITe7	SOICT	xuan.vt3451	12092004
20226791	001234567833	Đặng Văn Yên	M	2004-11-17	ITe7	SOICT	yen.dv6791	17112004
20225482	001234567855	Nguyễn Thị Ánh	F	2004-01-09	ITe7	SOICT	anh.nt5482	09012004
20221465	001234567844	Hoàng Văn Bình	M	2004-02-07	ITe7	SOICT	binh.hv1465	07022004
20223589	001234567877	Trần Thị Cúc	F	2004-03-13	ITe7	SOICT	cuc.tt3589	13032004
20227634	001234567811	Phạm Văn Dương	M	2004-05-02	ITe7	SOICT	duong.pv7634	02052004
20213336	025203782359	Hồ Thanh Tố	F	2003-12-15	FL1	FOFL	to.ht3336	15122003
20214447	025203782360	Lã Hoàng Khiêm	M	2003-01-20	MI2	FAMI	khiem.lh4447	20012003
20215558	025203782361	Quách Ngọc Quang	M	2003-04-09	EE1	SEEE	quang.qn5558	09042003
20216669	025203782362	Phan Thị Diễm	F	2003-11-03	FL1	FOFL	diem.pt6669	03112003
20217780	025203782363	Đào Minh Phan	M	2003-05-18	MI2	FAMI	phan.dm7780	18052003
20218891	025203782364	Diễm Văn Quách	M	2003-09-14	EE1	SEEE	quach.dv8891	14092003
20213337	025203782365	Đoàn Thanh Đại	M	2003-06-06	FL1	FOFL	dai.dt3337	06062003
20214448	025203782366	Đại Đức Khiêm	M	2003-12-09	MI2	FAMI	khiem.dd4448	09122003
20215559	025203782367	Lã Ngọc Tố	F	2003-10-07	EE1	SEEE	to.ln5559	07102003
20216670	025203782368	Phan Hoàng Lã	M	2003-03-19	FL1	FOFL	la.ph6670	19032003
20217781	025203782369	Tố Văn Diễm	F	2003-02-27	MI2	FAMI	diem.tv7781	27022003
20218892	025203782370	Trương Thị Đào	F	2003-07-13	EE1	SEEE	dao.tt8892	13072003
20213338	025203782371	Quách Ngọc Trần	M	2003-05-04	FL1	FOFL	tran.qn3338	04052003
20214449	025203782372	Cồ Văn Đại	M	2003-09-21	MI2	FAMI	dai.cv4449	21092003
20215560	025203782373	Hồ Thị Lã	F	2003-05-18	EE1	SEEE	la.ht5560	18052003
20216671	025203782374	Đào Minh Khiêm	M	2003-03-29	FL1	FOFL	khiem.dm6671	29032003
20217782	025203782375	Đại Thị Tố	F	2003-04-03	MI2	FAMI	to.dt7782	03042003
20218893	025203782376	Phan Văn Quách	M	2003-08-04	EE1	SEEE	quach.pv8893	04082003
20213339	025203782377	Trần Ngọc Diễm	F	2003-09-17	FL1	FOFL	diem.tn3339	17092003
20214450	025203782378	Vũ Đức Khiêm	M	2003-10-25	MI2	FAMI	khiem.vd4450	25102003
\.


--
-- Data for Name: study_time; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.study_time (clazz_id, semester_id, dow, start_time, finish_time) FROM stdin;
400001	20241	Monday	06:45:00	09:30:00
400005	20241	Monday	09:45:00	12:30:00
400006	20241	Monday	14:15:00	17:00:00
400007	20241	Wednesday	06:45:00	09:30:00
400008	20241	Wednesday	09:45:00	12:30:00
410001	20241	Tuesday	06:45:00	09:30:00
410002	20241	Tuesday	09:45:00	12:30:00
420003	20241	Thursday	06:45:00	09:30:00
420004	20241	Thursday	09:45:00	12:30:00
700001	20241	Monday	12:30:00	15:15:00
700002	20241	Monday	15:30:00	18:15:00
700003	20241	Monday	18:30:00	21:15:00
710001	20241	Tuesday	12:30:00	15:15:00
710002	20241	Tuesday	15:30:00	18:15:00
710003	20241	Tuesday	18:30:00	21:15:00
720001	20241	Wednesday	06:45:00	09:30:00
720002	20241	Wednesday	09:45:00	12:30:00
720003	20241	Wednesday	12:30:00	15:15:00
730001	20241	Friday	06:45:00	09:30:00
730002	20241	Friday	09:45:00	12:30:00
730003	20241	Friday	12:30:00	15:15:00
740001	20241	Monday	06:45:00	09:30:00
740002	20241	Monday	09:45:00	12:30:00
740003	20241	Monday	14:15:00	17:00:00
900001	20241	Tuesday	06:45:00	09:30:00
900002	20241	Tuesday	09:45:00	12:30:00
900004	20241	Thursday	09:45:00	12:30:00
100001	20232	Monday	08:00:00	10:00:00
730001	20241	Monday	08:00:00	10:00:00
900003	20241	Thursday	06:50:00	09:30:00
700001	20232	Monday	06:45:00	09:30:00
700002	20232	Monday	09:45:00	12:30:00
700003	20232	Monday	14:15:00	17:00:00
710001	20232	Tuesday	06:45:00	09:30:00
710002	20232	Tuesday	09:45:00	12:30:00
710003	20232	Tuesday	14:15:00	17:00:00
720001	20232	Wednesday	06:45:00	09:30:00
720002	20232	Wednesday	09:45:00	12:30:00
720003	20232	Wednesday	12:30:00	15:15:00
730001	20232	Thursday	06:45:00	09:30:00
730002	20232	Thursday	09:45:00	12:30:00
730003	20232	Thursday	12:30:00	15:15:00
740001	20232	Friday	06:45:00	09:30:00
740002	20232	Friday	09:45:00	12:30:00
740003	20232	Friday	12:30:00	15:15:00
750001	20232	Monday	06:45:00	09:30:00
750002	20232	Monday	09:45:00	12:30:00
100001	20232	Tuesday	06:45:00	09:30:00
100002	20232	Tuesday	09:45:00	12:30:00
100003	20232	Thursday	06:45:00	09:30:00
100004	20232	Thursday	09:45:00	12:30:00
400001	20242	Monday	06:45:00	09:30:00
400005	20242	Monday	09:45:00	12:30:00
400006	20242	Monday	12:45:00	15:30:00
400007	20242	Wednesday	06:45:00	09:30:00
400008	20242	Wednesday	09:45:00	12:30:00
410001	20242	Tuesday	06:45:00	09:30:00
410002	20242	Tuesday	09:45:00	12:30:00
420003	20242	Thursday	06:45:00	09:30:00
420004	20242	Thursday	09:45:00	12:30:00
100001	20242	Tuesday	06:45:00	09:30:00
100002	20242	Tuesday	09:45:00	12:30:00
100003	20242	Thursday	06:45:00	09:30:00
100004	20242	Thursday	09:45:00	12:30:00
\.


--
-- Data for Name: subject; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.subject (subject_id, subject_name, institute_id, credit, final_coefficient) FROM stdin;
IT0002	Introduction to Artificial Technology	SOICT	3	0.5
IT0003	Introduction to Communication Technology	SOICT	2	0.4
IT0004	Database	SOICT	3	0.4
IT0005	Operating System	SOICT	2	0.3
MI0006	Discrete Math	FAMI	3	0.5
FL0001	Dealing With Text	FOFL	2	0.3
FL0002	Technical Writing and Presentation	FOFL	3	0.4
EP0001	Physics	FEP	4	0.4
EP0002	Physics 2	FEP	2	0.3
LS0001	Biology	SCLS	4	0.5
MI0001	Linear Algebra	FAMI	4	0.3
EE0001	Electromagnetism	SEEE	4	0.5
MI0002	Differential Equations	FAMI	3	0.5
SM0001	Economics	SEM	1	0.2
MI0003	Statistics	FAMI	1	0.4
ME0001	Engineering Mechanics	SME	1	0.3
ED0001	Sociology	FED	3	0.3
IT0001	Computer Science	SOICT	4	0.5
ED0002	Psychology	FED	3	0.4
ME0002	Thermodynamics	SME	2	0.5
MI0004	Calculus 1	FAMI	2	0.5
MI0005	Calculus 2	FAMI	2	0.4
\.


--
-- Data for Name: teach; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.teach (clazz_id, semester_id, lecturer_id, room, max_student) FROM stdin;
100001	20221	100007	D9 - 201	120
100001	20212	100007	D9 - 201	120
100002	20221	101007	D9 - 301	60
100002	20212	101007	D9 - 301	60
100003	20221	100020	D9 - 202	120
100003	20212	100020	D9 - 202	120
100004	20221	100203	D9 - 202	120
100004	20212	100203	D9 - 202	120
100005	20221	101020	D9 - 302	60
100005	20212	101020	D9 - 302	60
400001	20221	100018	D3 - 201	120
400001	20212	100018	D3 - 201	120
400005	20221	100018	D3 - 205	60
400005	20212	100018	D3 - 205	60
400006	20221	100201	D3 - 206	60
400006	20212	100201	D3 - 206	60
400007	20221	100206	D3 - 207	60
400007	20212	100206	D3 - 207	60
400008	20221	101018	D3 - 208	60
700001	20241	100006	D3 - 201	120
700002	20241	100006	D3 - 201	120
700003	20241	100019	D3 - 201	40
710001	20241	100019	D3 - 201	120
710002	20241	100019	D3 - 201	120
710003	20241	100202	D3 - 201	40
720001	20241	100202	D3 - 203	120
720002	20241	100202	D3 - 203	120
720003	20241	101006	D3 - 303	40
730001	20241	101006	D3 - 204	120
730002	20241	101006	D3 - 204	120
730003	20241	101019	D3 - 304	40
740001	20241	101019	D3 - 205	120
740002	20241	101019	D3 - 205	120
740003	20241	101032	D3 - 305	40
750001	20241	101032	D3 - 206	60
750002	20241	101032	D3 - 206	60
700001	20232	101006	D3 - 201	120
700002	20232	101032	D3 - 201	120
700003	20232	100202	D3 - 201	40
710001	20232	101019	D3 - 201	120
710002	20232	100019	D3 - 201	120
710003	20232	100006	D3 - 201	40
720001	20232	100019	D3 - 203	120
720002	20232	101032	D3 - 203	120
720003	20232	100006	D3 - 303	40
730001	20232	100006	D3 - 204	120
730002	20232	101019	D3 - 204	120
730003	20232	100202	D3 - 304	40
740001	20232	100202	D3 - 205	120
740002	20232	101032	D3 - 205	120
740003	20232	101019	D3 - 305	40
750001	20232	100019	D3 - 206	60
750002	20232	101006	D3 - 206	60
100001	20241	100007	D9 - 201	120
100003	20241	100020	D9 - 202	120
100004	20241	100203	D9 - 202	120
100002	20241	101007	D9 - 301	60
100005	20241	101020	D9 - 302	60
100001	20232	100007	D9 - 201	120
100003	20232	100020	D9 - 202	120
100004	20232	100203	D9 - 202	120
100002	20232	101007	D9 - 301	60
100005	20232	101020	D9 - 302	60
100001	20242	100007	D9 - 201	120
100003	20242	100020	D9 - 202	120
100004	20242	100203	D9 - 202	120
100002	20242	101007	D9 - 301	60
100005	20242	101020	D9 - 302	60
400001	20241	100018	D3 - 201	120
410001	20241	100201	D3 - 202	120
410002	20241	100206	D3 - 202	120
420003	20241	101018	D3 - 203	120
420004	20241	101031	D3 - 204	120
400005	20241	100018	D3 - 205	60
400006	20241	100201	D3 - 206	60
400007	20241	100206	D3 - 207	60
400008	20241	101018	D3 - 208	60
400001	20242	100018	D3 - 201	120
410001	20242	100201	D3 - 202	120
410002	20242	100206	D3 - 202	120
420003	20242	101018	D3 - 203	120
420004	20242	101031	D3 - 204	120
400005	20242	100018	D3 - 205	60
400006	20242	100201	D3 - 206	60
400007	20242	100206	D3 - 207	60
400008	20242	101018	D3 - 208	60
900001	20241	100017	D9 - 201	60
900002	20241	101017	D9 - 202	60
900004	20241	100017	D9 - 302	60
900003	20241	101030	D9 - 301	60
400008	20212	101018	D3 - 208	60
410001	20221	100201	D3 - 202	120
410001	20212	100201	D3 - 202	120
410002	20221	100206	D3 - 202	120
410002	20212	100206	D3 - 202	120
\.


--
-- Data for Name: tutor; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tutor (tutor_id, father_name, father_dob, father_job, father_phonenumber, mother_name, mother_dob, mother_job, mother_phonenumber) FROM stdin;
20211234	Nguyễn Văn An	1980-03-15	farmer	0281234567	Trần Thị Bằng	1982-07-22	teacher	0387654321
20213333	Lê Minh Chiến\n	1975-05-10	engineer	0276543210	Phan Thị Dinh	1980-11-30	nurse	0398765432
20213334	Trần Văn Em	1983-02-28	farmer	0298765432	Nguyễn Thị Phúc	1979-09-17	doctor	0389876543
20213335	Vũ Tiến Giang	1972-08-05	teacher	0212345678	Hoàng Thị Hồng	1984-01-12	farmer	0398765123
20213336	Đoàn Minh Khôi	1981-10-20	farmer	0256789123	Lý Thị Dậu	1977-03-10	teacher	0381234590
20213337	Phạm Quang Khải	1980-01-22	nurse	0209876543	Bùi Thị Linh	1983-06-25	engineer	0396543210
20213338	Cao Thành Mẫn	1976-12-18	farmer	0212345987	Nguyễn Thị Nở	1982-05-14	nurse	0387654098
20213339	Hoàng Tấn Oanh	1983-11-03	doctor	0276549890	Trương Thị Phúc	1980-02-16	farmer	0399876123
20214444	Lâm Thái Quỳnh	1982-09-08	engineer	0203456789	Phan Thị Rành	1984-06-30	teacher	0385432190
20214445	Ngô Trung Sĩ	1979-04-14	farmer	0298765432	Hồ Thị Tình	1981-03-25	nurse	0398765098
20214446	Vũ Phúc Úc	1981-07-11	teacher	0285432198	Nguyễn Thị Vân	1978-05-06	farmer	0386543219
20214447	Trịnh Thế Quân	1975-01-29	farmer	0223456789	Lê Thị Xuyến	1980-04-22	engineer	0391234567
20214448	Phan Lệ Yến	1980-03-03	nurse	0298765432	Trương Thị Điệu	1979-11-10	farmer	0384321987
20214449	Đoàn Đức Anh	1980-06-10	farmer	0223456987	Vũ Thị Bích	1982-11-21	engineer	0398765431
20214450	Lê Thanh Cường	1978-02-25	doctor	0298765123	Nguyễn Thị Diễm	1983-08-14	teacher	0389876541
20215555	Trần Thiên Duy	1977-09-11	farmer	0212345987	Hoàng Thị Minh	1984-04-17	doctor	0394321098
20215556	Nguyễn Quang Hùng	1980-05-03	nurse	0287654321	Lê Thị Hương	1981-12-05	farmer	0381234598
20215557	Vũ Minh Tâm	1982-07-22	engineer	0209876543	Phan Thị Lan	1979-10-30	farmer	0396549876
20215558	Trịnh Thế Kiên	1975-04-15	farmer	0212345679	Nguyễn Thị Lệ	1982-01-18	teacher	0385432101
20215559	Lâm Ngọc Tùng	1983-12-05	nurse	0298765432	Cao Thị Ngọc	1980-09-25	doctor	0399876543
20215560	Phan Hùng Sơn	1976-11-12	teacher	0223456789	Trần Thị Thanh	1984-03-14	engineer	0387654322
20216666	Vũ Tiến Đức	1981-01-22	farmer	0287654320	Bùi Thị Thu	1983-06-10	nurse	0391234569
20216667	Ngô Đức Sơn	1979-03-05	doctor	0209876543	Hoàng Thị Tuyết	1980-12-17	farmer	0398765439
20216668	Lê Trung Quân	1982-04-18	teacher	0298765098	Trương Thị Vân	1976-08-26	nurse	0384321098
20216669	Trần Hữu Quang	1978-06-09	farmer	0212345789	Vũ Thị Xuyến	1983-11-22	farmer	0397654322
20216670	Phan Duy Hùng	1980-10-17	nurse	0223456980	Nguyễn Thị Mai	1982-02-08	engineer	0389876540
20216671	Cao Đức Huy	1975-12-11	farmer	0298765212	Lê Thị Lan	1984-07-04	teacher	0398765122
20217777	Trương Hải Hoàng	1979-01-08	farmer	0212345678	Phan Thị Linh	1981-03-29	nurse	0386543213
20217778	Nguyễn Quang Thái	1983-07-21	doctor	0223456890	Vũ Thị Kim	1977-10-17	teacher	0395432108
20217779	Lâm Quang Duy	1981-11-14	engineer	0298765401	Trần Thị Hương	1980-04-28	farmer	0389876546
20217780	Phan Hùng Mạnh	1982-03-27	farmer	0212345986	Nguyễn Thị Ngọc	1978-06-05	nurse	0398765437
20217781	Vũ Thiên Phúc	1978-08-13	teacher	0223456712	Lê Thị Lan	1983-12-23	engineer	0387654325
20217782	Ngô Minh Huy	1981-09-30	doctor	0212345985	Trương Thị Kiều	1982-11-18	farmer	0397654328
20218888	Lê Đình Tuấn	1976-01-09	nurse	0298765430	Nguyễn Thị Lan	1980-02-20	farmer	0389876542
20218889	Phan Trung Phát	1983-04-22	teacher	0212345689	Vũ Thị Diễm	1981-10-15	nurse	0398765436
20218890	Trương Đình Hoàng	1980-12-11	farmer	0223456895	Nguyễn Thị Thu	1982-05-03	doctor	0396543214
20218891	Lâm Tiến Phúc	1977-07-16	nurse	0298765438	Phan Thị My	1984-08-29	teacher	0384321099
20218892	Ngô Minh Khôi	1980-09-04	farmer	0212345671	Trần Thị Mai	1976-03-25	engineer	0395432100
20218893	Lê Thiện Quân	1978-05-15	farmer	0287654321	Nguyễn Thị Lan	1982-11-29	teacher	0398765432
20221025	Trần Hoàng Bảo	1981-02-22	doctor	0298765432	Vũ Thị Yến	1980-08-10	nurse	0387654321
20221026	Nguyễn Văn Trường	1975-04-11	farmer	0209876543	Cao Thị Mỹ	1984-09-17	teacher	0396543210
20221231	Phan Duy Hùng	1980-03-22	engineer	0287654329	Lê Thị Ngọc	1983-12-30	nurse	0394321098
20221234	Vũ Minh Lâm	1979-08-03	farmer	0223456789	Nguyễn Thị Thu	1981-05-21	doctor	0398765430
20221243	Lâm Thanh Sơn	1976-06-17	nurse	0212345671	Trần Thị My	1980-02-12	engineer	0394321099
20221245	Trương Hải Duy	1978-01-06	farmer	0209876541	Nguyễn Thị Duyên	1983-04-19	teacher	0389876542
20221256	Ngô Thiên Anh	1980-10-22	doctor	0223456890	Hoàng Thị Thủy	1982-06-28	farmer	0398765439
20221278	Trần Văn Kiên	1977-09-11	teacher	0287654390	Vũ Thị Lệ	1981-07-15	engineer	0385432101
20221452	Phan Quang Đạt	1982-12-02	nurse	0298765401	Nguyễn Thị Phương	1980-03-30	farmer	0398765438
20221465	Lê Tấn Lộc	1979-10-29	farmer	0212345678	Trương Thị Diễm	1982-08-22	doctor	0397654320
20221468	Vũ Hoàng Khôi	1981-05-13	engineer	0223456781	Nguyễn Thị Tuyết	1983-12-09	nurse	0387654324
20221489	Trương Hồng Sơn	1980-07-05	nurse	0212345890	Lê Thị Bảo	1981-02-16	farmer	0396543213
20221493	Nguyễn Hữu Linh	1981-01-20	doctor	0223456785	Trần Thị Thảo	1983-03-11	teacher	0399876547
20221976	Lê Quang Duy	1983-09-12	teacher	0298765434	Cao Thị Hoài	1980-11-21	farmer	0397654329
20221987	Trần Quang Tú	1978-02-01	farmer	0212345689	Nguyễn Thị Lan	1982-07-29	nurse	0394321092
20222134	Vũ Đức Duy	1981-12-11	doctor	0223456790	Hoàng Thị Quỳnh	1979-11-05	engineer	0398765435
20222167	Nguyễn Minh Tín	1980-09-22	nurse	0212345768	Lê Thị Thanh	1983-06-10	teacher	0398765434
20222345	Trương Bảo Lộc	1977-11-30	engineer	0223456791	Nguyễn Thị Huỳnh	1980-12-23	farmer	0394321096
20222367	Lâm Thanh Tuấn	1979-12-20	farmer	0209876547	Cao Thị Nhi	1984-02-18	doctor	0397654321
20222540	Trần Hoàng Tiến	1983-07-07	nurse	0212345760	Lê Thị Phúc	1980-01-29	farmer	0398765433
20222541	Nguyễn Tùng Phát	1982-10-10	engineer	0287654310	Nguyễn Thị Thu	1981-08-14	teacher	0399876540
20223080	Vũ Thanh An	1977-12-14	doctor	0223456702	Lê Thị Hồng	1983-03-04	nurse	0387654320
20223081	Phan Đức Thái	1980-09-14	teacher	0298765439	Nguyễn Thị Lan	1981-06-11	farmer	0397654325
20223210	Trương Minh Dương	1981-11-03	farmer	0223456760	Vũ Thị Thanh	1978-03-17	doctor	0394321093
20223219	Lê Thiện Khang	1983-06-01	nurse	0212345690	Nguyễn Thị Thu	1982-01-02	teacher	0398765436
20223333	Nguyễn Hữu Tiến	1977-10-25	farmer	0212345702	Trần Thị Lệ	1980-11-09	engineer	0396543211
20223334	Trần Quốc Vương	1981-08-14	doctor	0287654328	Lê Thị Thi	1983-10-15	farmer	0397654327
20223335	Lâm Quang Tài	1979-05-30	nurse	0223456793	Nguyễn Thị Lan	1980-06-20	teacher	0399876542
20223336	Phan Hữu Duy	1983-02-10	engineer	0298765409	Cao Thị Minh	1981-11-23	farmer	0397654326
20223337	Trương Đức Long	1978-04-01	teacher	0223456787	Nguyễn Thị Quỳnh	1980-12-14	nurse	0394321094
20223338	Lê Thanh Phúc	1980-07-15	farmer	0212345675	Vũ Thị Thi	1982-04-06	doctor	0397654320
20223339	Vũ Quang Khải	1983-05-09	nurse	0223456794	Nguyễn Thị Kiều	1981-03-11	teacher	0399876544
20223451	Nguyễn Hoàng Quý	1977-09-23	farmer	0212345698	Lê Thị Duyên	1983-11-10	doctor	0397654323
20223456	Trần Thiên Chí	1982-03-03	engineer	0223456704	Nguyễn Thị Thanh	1980-12-21	nurse	0398765437
20223567	Lê Thiện Hoàng	1980-05-15	doctor	0223456789	Trần Thị Lan	1982-04-02	nurse	0394321095
20223589	Nguyễn Hoàng Duy	1978-10-29	farmer	0209876543	Cao Thị Lệ	1983-09-18	farmer	0397654328
20223641	Vũ Minh Hậu	1982-06-11	teacher	0212345692	Nguyễn Thị Thu	1980-05-16	nurse	0398765435
20223645	Trần Hữu Thành	1980-07-10	engineer	0223456782	Lê Thị Thi	1981-12-11	farmer	0394321097
20223945	Nguyễn Hữu Duy	1979-09-14	nurse	0298765432	Trương Thị Mai	1983-08-19	teacher	0399876541
20223987	Lê Hoàng Phúc	1983-01-18	doctor	0212345687	Nguyễn Thị Lan	1978-10-07	engineer	0397654329
20224075	Trương Quang Lộc	1981-04-12	farmer	0223456792	Lê Thị Bích	1982-01-28	farmer	0398765436
20224076	Nguyễn Quang Tài	1980-03-23	nurse	0209876549	Trần Thị Diệu	1984-02-19	teacher	0397654325
20224321	Phan Hữu An	1982-08-30	engineer	0287654326	Cao Thị Ngọc	1983-07-15	farmer	0394321099
20224356	Lê Quang Lương	1977-05-11	doctor	0212345695	Nguyễn Thị Thu	1981-10-12	nurse	0398765434
20224390	Trần Thiên Bình	1979-02-25	nurse	0223456783	Lê Thị Thảo	1980-09-04	teacher	0397654324
20224444	Nguyễn Thiện Khang	1981-11-10	farmer	0287654322	Trần Thị Hoa	1983-03-20	doctor	0394321090
20224445	Lê Thiên Khải	1982-10-06	teacher	0212345789	Nguyễn Thị Duyên	1980-05-29	farmer	0397654322
20224446	Trần Quang Minh	1978-08-18	nurse	0298765438	Lê Thị Kỳ	1981-11-06	engineer	0398765433
20224447	Phan Đình Duy	1977-11-22	doctor	0212345696	Trương Thị Vân	1980-02-10	teacher	0394321093
20224448	Lê Hoàng Kiên	1981-03-15	engineer	0223456784	Nguyễn Thị Kim	1982-05-20	nurse	0397654321
20224449	Trương Đức Khang	1983-07-19	farmer	0298765400	Vũ Thị Lan	1980-01-14	doctor	0399876540
20224450	Nguyễn Thanh Minh	1982-09-08	teacher	0223456781	Nguyễn Thị Quyên	1981-07-21	farmer	0398765431
20224456	Vũ Quang Vinh	1979-06-20	nurse	0209876545	Lê Thị Thanh	1980-09-05	teacher	0397654327
20224489	Nguyễn Tùng Duy	1983-11-08	farmer	0212345701	Trương Thị Lan	1979-04-03	doctor	0394321091
20224521	Lê Quang Thành	1980-12-02	engineer	0223456796	Nguyễn Thị Kim	1981-01-11	nurse	0397654328
20224567	Trần Minh Duy	1978-04-18	doctor	0212345790	Nguyễn Thị Thảo	1983-02-15	teacher	0394321092
20224589	Phan Hữu Kiên	1982-01-24	teacher	0223456799	Lê Thị Thi	1980-12-17	nurse	0399876546
20224612	Trương Quang Vinh	1977-02-03	farmer	0287654324	Nguyễn Thị Lan	1983-06-09	engineer	0397654323
20224657	Nguyễn Hồng Sơn	1981-07-23	nurse	0223456795	Trần Thị Thu	1982-05-25	farmer	0394321094
20224734	Lê Minh Kiên	1982-02-14	doctor	0298765437	Trương Thị Lan	1980-03-18	nurse	0397654329
20224735	Trần Thiện Duy	1983-06-20	farmer	0223456780	Nguyễn Thị Lan	1980-11-22	teacher	0399876543
20225431	Nguyễn Quang Kiên	1979-07-25	nurse	0212345681	Lê Thị Hoa	1982-09-17	engineer	0397654320
20225432	Trương Hữu Tài	1980-12-19	teacher	0287654320	Nguyễn Thị Kim	1981-03-09	farmer	0398765439
20225467	Lê Hữu Sơn	1977-01-14	farmer	0212345793	Trần Thị Hương	1983-02-04	doctor	0397654324
20225478	Phan Thanh An	1982-10-30	nurse	0223456788	Lê Thị Thu	1980-05-12	farmer	0394321096
20225482	Nguyễn Quang Minh	1980-04-20	teacher	0212345693	Trần Thị Vân	1982-11-29	nurse	0397654321
20225555	Trương Quang Duy	1979-12-05	farmer	0223456797	Nguyễn Thị Thu	1981-09-03	doctor	0399876541
20225556	Lê Hữu Duy	1983-03-19	engineer	0212345794	Nguyễn Thị Hòa	1982-07-30	nurse	0397654323
20225557	Nguyễn Minh Thành	1978-11-08	nurse	0223456786	Lê Thị Lệ	1983-05-21	teacher	0394321090
20225558	Nguyễn Thiện Tùng	1981-11-25	farmer	0212345679	Trần Thị Duyên	1980-03-28	teacher	0397654325
20225559	Phan Quang Thành	1978-06-30	nurse	0223456798	Lê Thị Thanh	1983-01-10	doctor	0394321098
20225560	Trương Hữu Lộc	1983-09-17	doctor	0212345683	Nguyễn Thị Thu	1982-05-19	farmer	0397654327
20225674	Nguyễn Hoàng Kỳ	1979-08-04	teacher	0298765435	Trần Thị Hoa	1981-07-28	nurse	0394321093
20225678	Trương Minh Đạt	1980-11-21	farmer	0212345670	Lê Thị Lan	1983-03-14	doctor	0398765430
20225735	Phan Thiện Quang	1983-06-01	nurse	0223456785	Trần Thị Kim	1980-09-09	teacher	0397654329
20225736	Lê Quang Tài	1981-12-18	engineer	0223456782	Nguyễn Thị Thảo	1983-04-30	farmer	0394321095
20226000	Trương Hoàng Duy	1978-02-23	nurse	0212345795	Lê Thị Thi	1980-08-11	doctor	0399876542
20226001	Phan Hồng Tài	1980-06-04	farmer	0223456794	Nguyễn Thị Lan	1981-11-17	teacher	0397654322
20226215	Trần Thiên Lâm	1983-04-07	teacher	0212345789	Nguyễn Thị Diệu	1982-09-14	doctor	0397654324
20226216	Lê Minh Quân	1979-07-23	farmer	0223456702	Trương Thị Thu	1981-05-09	nurse	0394321097
20226531	Nguyễn Hữu Long	1981-01-13	doctor	0212345785	Lê Thị Hòa	1980-11-22	teacher	0397654326
20226547	Trương Minh Khang	1983-02-04	engineer	0212345791	Nguyễn Thị Thu	1982-04-08	farmer	0399876543
20226666	Phan Quang Bảo	1981-08-13	teacher	0223456793	Trần Thị Lan	1983-10-12	doctor	0394321096
20226667	Nguyễn Thiên Sơn	1982-07-19	nurse	0223456788	Lê Thị Bảo	1980-02-02	engineer	0397654321
20226668	Lê Thiên Hồng	1983-05-01	doctor	0298765436	Nguyễn Thị Duyên	1981-12-04	teacher	0394321099
20226669	Trần Minh Hữu	1981-09-09	farmer	0223456791	Lê Thị Kim	1982-11-11	nurse	0397654320
20226670	Phan Hữu Sơn	1979-11-29	teacher	0212345701	Nguyễn Thị Thủy	1983-06-23	doctor	0394321092
20226671	Lê Hoàng Khải	1982-10-04	nurse	0223456784	Trương Thị Lệ	1981-05-30	teacher	0397654323
20226734	Trương Quang Đức	1978-01-18	engineer	0212345696	Nguyễn Thị Hòa	1983-12-25	nurse	0394321094
20226741	Nguyễn Thiên Vũ	1983-08-12	farmer	0223456790	Trần Thị Lan	1982-05-06	doctor	0397654328
20226783	Lê Quang Bình	1977-12-27	nurse	0212345797	Nguyễn Thị Thanh	1983-04-03	engineer	0394321091
20226789	Phan Minh Lâm	1980-03-13	doctor	0298765433	Lê Thị Thu	1982-09-14	teacher	0397654329
20226791	Nguyễn Hoàng Khoa	1982-08-21	farmer	0223456705	Trần Thị Diệu	1981-12-27	nurse	0399876545
20227634	Trương Thiên Tài	1979-09-25	engineer	0223456789	Nguyễn Thị Quỳnh	1982-06-22	doctor	0394321090
20227635	Nguyễn Minh Bình	1981-04-06	teacher	0212345706	Lê Thị Thanh	1980-07-19	nurse	0397654324
20227636	Lê Hữu Quang	1982-11-16	nurse	0223456783	Trần Thị Thu	1981-02-10	doctor	0397654325
20227654	Phan Quang Sơn	1981-05-14	doctor	0212345794	Lê Thị Duyên	1982-08-02	teacher	0394321093
20227689	Nguyễn Thiên Thảo	1982-12-29	nurse	0298765439	Trương Thị Lan	1980-05-23	farmer	0397654326
20227777	Lê Hoàng Tài	1980-04-09	farmer	0212345787	Nguyễn Thị Minh	1983-02-01	doctor	0394321098
20227778	Nguyễn Hoàng Bình	1983-05-10	teacher	0223456795	Trần Thị Thanh	1981-01-20	nurse	0397654327
20227779	Trương Thiên Duy	1982-09-22	engineer	0212345708	Nguyễn Thị Lan	1980-08-15	doctor	0399876549
20227780	Lê Minh Tài	1978-07-17	farmer	0223456792	Trần Thị Hồng	1983-12-14	teacher	0394321097
20227781	Nguyễn Thiên Lộc	1983-01-13	doctor	0212345702	Trương Thị Lệ	1980-06-23	nurse	0397654328
20227782	Trương Hữu Tài	1979-02-19	nurse	0223456786	Nguyễn Thị Mai	1982-03-04	engineer	0397654329
20227812	Nguyễn Hữu Quang	1981-03-29	farmer	0223456781	Lê Thị Thu	1982-04-23	teacher	0394321099
20227823	Trương Minh Đức	1983-01-05	nurse	0212345700	Nguyễn Thị Lan	1980-10-18	engineer	0397654322
20227856	Lê Hoàng Sơn	1982-11-10	teacher	0223456790	Trương Thị Thu	1983-02-12	nurse	0397654326
20227890	Nguyễn Thiên Phúc	1978-10-02	doctor	0212345694	Lê Thị Thanh	1983-07-06	farmer	0394321094
20227891	Trương Quang Sơn	1980-05-30	nurse	0223456784	Nguyễn Thị Hoa	1982-01-11	teacher	0399876540
20227892	Phan Hoàng Vũ	1981-12-14	farmer	0212345788	Trần Thị Hương	1980-06-27	engineer	0397654327
20227893	Lê Thiên Bình	1982-08-23	engineer	0223456793	Nguyễn Thị Quỳnh	1983-04-05	doctor	0394321095
20228311	Nguyễn Minh Sơn	1978-09-17	teacher	0212345699	Trương Thị Duyên	1983-03-04	nurse	0397654323
20228312	Trương Minh Hùng	1981-04-11	nurse	0223456795	Nguyễn Thị Thảo	1982-12-22	engineer	0394321092
20228734	Lê Minh Duy	1983-11-20	doctor	0223456796	Nguyễn Thị Kim	1980-02-13	farmer	0399876547
20228791	Nguyễn Quang Hải	1982-10-07	engineer	0212345781	Trương Thị Bích	1983-06-25	nurse	0394321098
20228865	Trương Hồng Vũ	1983-05-13	nurse	0223456782	Nguyễn Thị Thảo	1980-07-19	teacher	0397654324
20228872	Phan Minh Thiên	1980-08-09	doctor	0212345707	Lê Thị Lan	1982-04-27	farmer	0394321096
20228888	Nguyễn Thiên Tài	1981-10-17	teacher	0223456783	Trương Thị Minh	1980-05-01	nurse	0397654325
20228889	Trương Quang Hòa	1983-03-26	farmer	0223456792	Lê Thị Diệu	1981-02-13	doctor	0399876544
20228890	Nguyễn Hữu Lộc	1980-12-06	engineer	0212345708	Trương Thị Hằng	1982-08-30	teacher	0397654326
20228891	Phan Thiên Quang	1983-07-11	doctor	0223456799	Nguyễn Thị Thanh	1980-10-25	farmer	0394321097
20228892	Lê Hoàng Thành	1982-05-22	nurse	0212345698	Trương Thị Lan	1981-11-06	engineer	0397654329
20228893	Nguyễn Quang Sơn	1979-01-03	farmer	0223456700	Lê Thị Hồng	1983-09-21	teacher	0397654323
20228899	Trương Thiện Bình	1983-12-14	engineer	0223456785	Nguyễn Thị Vân	1981-06-07	doctor	0394321094
20229102	Lê Quang Khang	1978-02-15	nurse	0212345709	Trương Thị Kim	1983-10-29	teacher	0397654328
20229103	Nguyễn Hoàng Sơn	1982-03-07	farmer	0223456791	Trần Thị Thảo	1983-06-11	engineer	0394321096
20229123	Lê Thiên Quang	1981-12-01	teacher	0223456780	Nguyễn Thị Diệu	1982-05-23	nurse	0397654324
20229145	Nguyễn Minh Khôi	1983-06-21	nurse	0223456797	Lê Thị Thi	1982-01-06	doctor	0399876543
20229378	Trương Minh Sơn	1982-04-19	doctor	0212345704	Nguyễn Thị Bích	1981-09-27	nurse	0397654325
20231221	Phan Hoàng Sơn	1983-05-24	engineer	0223456787	Nguyễn Thị Hương	1980-04-22	teacher	0394321093
20231226	Nguyễn Minh Sơn	1982-01-12	teacher	0212345703	Trần Thị Kim	1981-12-04	farmer	0397654326
20231230	Nguyễn Quang Hưng	1982-06-21	doctor	0223456790	Lê Thị Mai	1983-01-18	teacher	0397654321
20231231	Lê Hoàng Long	1981-11-14	teacher	0212345701	Trương Thị Lan	1982-09-08	nurse	0394321093
20231234	Trương Hoàng Thiên	1983-07-22	engineer	0223456789	Nguyễn Thị Thu	1980-06-04	doctor	0397654325
20231241	Nguyễn Minh Quang	1981-12-04	doctor	0212345792	Lê Thị Lan	1982-03-13	teacher	0394321094
20231245	Lê Hoàng Thi	1982-09-20	teacher	0223456782	Nguyễn Thị Thanh	1981-10-05	nurse	0397654327
20231246	Trương Minh Khoa	1982-02-15	engineer	0212345783	Lê Thị Hương	1982-01-24	doctor	0394321098
20231247	Nguyễn Hoàng Sơn	1981-09-09	nurse	0223456783	Trương Thị Hằng	1982-07-14	teacher	0397654329
20231249	Lê Thiên Vũ	1983-11-02	doctor	0223456793	Nguyễn Thị Quỳnh	1981-12-19	engineer	0394321097
20231389	Trương Hữu Duy	1982-10-13	teacher	0212345707	Lê Thị Hương	1982-02-06	farmer	0397654330
20234567	Lê Minh Thiên	1983-06-25	farmer	0223456795	Nguyễn Thị Lan	1980-03-21	nurse	0394321099
20235432	Nguyễn Thiên Quang	1983-03-11	engineer	0212345702	Trương Thị Thanh	1982-07-22	doctor	0397654331
20235454	Trương Quang Tài	1983-12-20	teacher	0223456786	Lê Thị Minh	1981-10-19	nurse	0394321095
20235455	Nguyễn Hoàng Sơn	1982-05-14	farmer	0212345781	Trương Thị Lan	1983-08-30	teacher	0397654332
20235478	Trương Hoàng Sơn	1981-04-21	doctor	0223456791	Lê Thị Hương	1982-05-02	engineer	0394321093
20235678	Lê Quang Sơn	1983-02-17	nurse	0212345705	Nguyễn Thị Thanh	1980-01-27	doctor	0397654333
20236578	Nguyễn Thiên Khoa	1983-09-14	teacher	0223456788	Lê Thị Diệu	1982-03-07	nurse	0394321096
20236587	Trương Minh Khoa	1981-01-15	engineer	0212345785	Nguyễn Thị Mai	1982-07-09	teacher	0397654334
20236756	Lê Hoàng Sơn	1982-11-25	farmer	0223456794	Nguyễn Thị Thủy	1981-08-06	engineer	0394321097
20236766	Nguyễn Thiên Thi	1981-07-10	nurse	0212345791	Lê Thị Duyên	1983-06-13	doctor	0397654335
20236789	Lê Hoàng Khoa	1982-09-14	teacher	0223456784	Trương Thị Hòa	1981-05-17	nurse	0394321098
20237654	Nguyễn Quang Sơn	1983-01-20	engineer	0223456792	Lê Thị Thủy	1980-12-29	farmer	0397654336
20237778	Lê Thiên Hoàng	1983-10-11	nurse	0212345708	Trương Thị Kim	1982-04-01	teacher	0394321099
20237890	Trương Minh Thi	1982-04-14	doctor	0223456780	Nguyễn Thị Lan	1983-01-29	nurse	0397654337
20237891	Nguyễn Minh Hùng	1981-05-17	farmer	0212345700	Trương Thị Mai	1982-11-24	engineer	0394321092
20237892	Lê Hoàng Thi	1983-02-05	teacher	0223456799	Nguyễn Thị Thanh	1980-10-18	doctor	0397654338
20237899	Trương Thiên Quang	1981-12-15	doctor	0212345793	Lê Thị Hương	1982-07-28	farmer	0394321095
20238901	Nguyễn Minh Quang	1983-04-02	nurse	0223456796	Trương Thị Lan	1980-01-13	teacher	0397654339
20238912	Lê Quang Bảo	1981-08-17	engineer	0212345782	Nguyễn Thị Thúy	1982-12-24	doctor	0394321096
20238921	Trương Thiên Khoa	1983-09-08	nurse	0223456781	Lê Thị Lan	1982-03-11	farmer	0397654340
20238965	Nguyễn Thiên Minh	1982-06-04	doctor	0212345789	Trương Thị Hằng	1981-01-09	engineer	0394321097
20238988	Lê Thiên Vũ	1981-11-29	teacher	0223456797	Nguyễn Thị Diệu	1983-04-10	nurse	0397654341
20238999	Nguyễn Quang Tài	1983-06-13	nurse	0212345706	Trương Thị Quỳnh	1980-02-05	teacher	0394321098
20239854	Trương Quang Sơn	1982-10-28	engineer	0223456795	Lê Thị Lan	1981-03-15	doctor	0397654342
20239855	Lê Thiên Sơn	1983-11-25	nurse	0212345794	Nguyễn Thị Mai	1982-06-17	farmer	0394321099
20239876	Nguyễn Minh Hoàng	1983-05-23	farmer	0223456782	Lê Thị Bích	1980-09-06	engineer	0397654343
20239877	Trương Hoàng Vũ	1981-09-01	teacher	0212345780	Nguyễn Thị Kim	1983-01-14	nurse	0394321096
20239889	Lê Hoàng Khoa	1982-12-10	nurse	0223456798	Trương Thị Thanh	1981-04-05	engineer	0397654344
20239988	Nguyễn Thiên Tài	1983-07-30	engineer	0212345790	Lê Thị Diệu	1982-10-14	teacher	0394321097
20239999	Trương Quang Vũ	1981-01-22	doctor	0223456787	Nguyễn Thị Quỳnh	1983-06-20	farmer	0397654345
20241256	Lê Minh Sơn	1982-08-28	nurse	0212345788	Trương Thị Hồng	1983-05-10	teacher	0394321099
\.


--
-- Name: clazz pk_clazz; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clazz
    ADD CONSTRAINT pk_clazz PRIMARY KEY (clazz_id);


--
-- Name: enroll pk_enroll; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enroll
    ADD CONSTRAINT pk_enroll PRIMARY KEY (student_id, clazz_id, semester_id);


--
-- Name: form_teacher pk_formteacher; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_teacher
    ADD CONSTRAINT pk_formteacher PRIMARY KEY (formteacher_id);


--
-- Name: give_conduct_point pk_giveconductpoint; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.give_conduct_point
    ADD CONSTRAINT pk_giveconductpoint PRIMARY KEY (student_id, semester_id);


--
-- Name: headmaster pk_headmaster; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.headmaster
    ADD CONSTRAINT pk_headmaster PRIMARY KEY (headmaster_id);


--
-- Name: institute pk_institute; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.institute
    ADD CONSTRAINT pk_institute PRIMARY KEY (institute_id);


--
-- Name: lecturer pk_lecturer; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lecturer
    ADD CONSTRAINT pk_lecturer PRIMARY KEY (lecturer_id);


--
-- Name: semester pk_semester; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.semester
    ADD CONSTRAINT pk_semester PRIMARY KEY (semester_id);


--
-- Name: student pk_student; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student
    ADD CONSTRAINT pk_student PRIMARY KEY (student_id);


--
-- Name: study_time pk_studytime; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.study_time
    ADD CONSTRAINT pk_studytime PRIMARY KEY (clazz_id, semester_id, dow, start_time);


--
-- Name: subject pk_subject; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subject
    ADD CONSTRAINT pk_subject PRIMARY KEY (subject_id);


--
-- Name: teach pk_teach; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teach
    ADD CONSTRAINT pk_teach PRIMARY KEY (clazz_id, semester_id);


--
-- Name: tutor pk_tutor; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tutor
    ADD CONSTRAINT pk_tutor PRIMARY KEY (tutor_id);


--
-- Name: class_information class_information_insert_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER class_information_insert_trigger INSTEAD OF INSERT ON public.class_information FOR EACH ROW EXECUTE FUNCTION public.class_information_insert();


--
-- Name: class_information class_information_update_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER class_information_update_trigger INSTEAD OF UPDATE ON public.class_information FOR EACH ROW EXECUTE FUNCTION public.class_information_update();


--
-- Name: enroll enroll_insert_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER enroll_insert_trigger BEFORE INSERT ON public.enroll FOR EACH ROW EXECUTE FUNCTION public.enroll_insert();


--
-- Name: give_conduct_point give_conduct_point_insert_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER give_conduct_point_insert_trigger BEFORE INSERT OR UPDATE ON public.give_conduct_point FOR EACH ROW EXECUTE FUNCTION public.give_conduct_point_insert();


--
-- Name: study_time insert_trigger_study_time; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER insert_trigger_study_time BEFORE INSERT ON public.study_time FOR EACH ROW EXECUTE FUNCTION public.insert_study_time();


--
-- Name: teach teach_insert_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER teach_insert_trigger BEFORE INSERT ON public.teach FOR EACH ROW EXECUTE FUNCTION public.teach_insert();


--
-- Name: study_time update_trigger_study_time; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_trigger_study_time BEFORE UPDATE ON public.study_time FOR EACH ROW EXECUTE FUNCTION public.update_study_time();


--
-- Name: clazz fk_clazz_subject; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clazz
    ADD CONSTRAINT fk_clazz_subject FOREIGN KEY (subject_id) REFERENCES public.subject(subject_id) ON UPDATE CASCADE;


--
-- Name: enroll fk_enroll_student; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enroll
    ADD CONSTRAINT fk_enroll_student FOREIGN KEY (student_id) REFERENCES public.student(student_id) ON UPDATE CASCADE;


--
-- Name: enroll fk_enroll_teach; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.enroll
    ADD CONSTRAINT fk_enroll_teach FOREIGN KEY (clazz_id, semester_id) REFERENCES public.teach(clazz_id, semester_id) ON UPDATE CASCADE;


--
-- Name: form_teacher fk_formteacher_institute; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_teacher
    ADD CONSTRAINT fk_formteacher_institute FOREIGN KEY (institute_id) REFERENCES public.institute(institute_id) ON UPDATE CASCADE;


--
-- Name: give_conduct_point fk_giveconductpoint_formteacher; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.give_conduct_point
    ADD CONSTRAINT fk_giveconductpoint_formteacher FOREIGN KEY (formteacher_id) REFERENCES public.form_teacher(formteacher_id) ON UPDATE CASCADE;


--
-- Name: give_conduct_point fk_giveconductpoint_semester; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.give_conduct_point
    ADD CONSTRAINT fk_giveconductpoint_semester FOREIGN KEY (semester_id) REFERENCES public.semester(semester_id) ON UPDATE CASCADE;


--
-- Name: give_conduct_point fk_giveconductpoint_student; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.give_conduct_point
    ADD CONSTRAINT fk_giveconductpoint_student FOREIGN KEY (student_id) REFERENCES public.student(student_id) ON UPDATE CASCADE;


--
-- Name: headmaster fk_headmaster_institute; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.headmaster
    ADD CONSTRAINT fk_headmaster_institute FOREIGN KEY (institute_id) REFERENCES public.institute(institute_id) ON UPDATE CASCADE;


--
-- Name: lecturer fk_lecturer_institute; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lecturer
    ADD CONSTRAINT fk_lecturer_institute FOREIGN KEY (institute_id) REFERENCES public.institute(institute_id) ON UPDATE CASCADE;


--
-- Name: student fk_student_institute; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student
    ADD CONSTRAINT fk_student_institute FOREIGN KEY (institute_id) REFERENCES public.institute(institute_id) ON UPDATE CASCADE;


--
-- Name: study_time fk_studytime_teach; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.study_time
    ADD CONSTRAINT fk_studytime_teach FOREIGN KEY (clazz_id, semester_id) REFERENCES public.teach(clazz_id, semester_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: subject fk_subject_institute; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.subject
    ADD CONSTRAINT fk_subject_institute FOREIGN KEY (institute_id) REFERENCES public.institute(institute_id) ON UPDATE CASCADE;


--
-- Name: teach fk_teach_clazz; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teach
    ADD CONSTRAINT fk_teach_clazz FOREIGN KEY (clazz_id) REFERENCES public.clazz(clazz_id) ON UPDATE CASCADE;


--
-- Name: teach fk_teach_lecturer; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teach
    ADD CONSTRAINT fk_teach_lecturer FOREIGN KEY (lecturer_id) REFERENCES public.lecturer(lecturer_id) ON UPDATE CASCADE;


--
-- Name: teach fk_teach_semester; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.teach
    ADD CONSTRAINT fk_teach_semester FOREIGN KEY (semester_id) REFERENCES public.semester(semester_id) ON UPDATE CASCADE;


--
-- Name: tutor fk_tutor_student; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tutor
    ADD CONSTRAINT fk_tutor_student FOREIGN KEY (tutor_id) REFERENCES public.student(student_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

