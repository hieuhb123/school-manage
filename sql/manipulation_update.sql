--------------STUDENT---------------------------------
-- Thời khóa biểu của sinh viên
-- input: student_id, semester_id
-- Các trường: mã lớp, mã học phần, tên học phần, thứ, thời gian, phòng học
SELECT ci.clazz_id, ci.subject_id, ci.subject_name, dow, start_time, finish_time, room
FROM enroll e
JOIN class_information ci USING (clazz_id, semester_id)
JOIN subject s USING (subject_id)
WHERE student_id = '20211234' AND semester_id = '20241'
ORDER BY dow, start_time;

-- Bảng điểm của học sinh
-- input: student_id
-- Các trường: semester, subject_id (mã học phần), tên học phần, tín chỉ, điểm học phần hệ 10, hệ 4 và điểm chữ
SELECT semester_id, t1.subject_id, subject_name, t1.credit, class_point, four_scale, alphabet_point
FROM subject_grades_of_students t1
JOIN subject USING (subject_id)
WHERE student_id = $1
ORDER BY semester_id;

-- Bảng đăng kí học phần trong kì hiện tại (ở chức năng đăng kí tín chỉ)
-- input: student, semester
-- Các trường: mã lớp, mã học phần, trạng thái đăng kí, tín chỉ, địa điểm học, thời gian học
SELECT DISTINCT ci.clazz_id, subject_id, 'Thành công' AS status, room, dow, start_time, finish_time
FROM enroll e
JOIN class_information ci USING (clazz_id, semester_id)
WHERE student_id = $1 AND semester_id = $2
ORDER BY dow, start_time;

-- Thông tin về điểm rèn luyện qua các kỳ + tên gvcn của kỳ đó
-- input: student_id
SELECT semester_id, formteacher_name, conduct_point
FROM give_conduct_point
JOIN form_teacher USING (formteacher_id)
WHERE student_id = $1
ORDER BY semester_id;

-- Xem GPA qua các kỳ
-- input: student_id
SELECT semester_id, gpa
FROM calculate_gpa
WHERE student_id = $1
ORDER BY semester_id;

---------------------LECTURER------------------------
-- Lấy thời khóa biểu của giáo viên theo kì (liệt kê các class trong 1 kỳ)
-- input: lecturer_id, semester_id
SELECT clazz_id, s.subject_id, subject_name, dow, start_time, finish_time, room
FROM class_information
JOIN subject s USING (subject_id)
WHERE lecturer_id = $1 AND semester_id = $2
ORDER BY semester_id;