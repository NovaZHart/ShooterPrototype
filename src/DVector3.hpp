#ifndef DVECTOR3_H
#define DVECTOR3_H

#include <cmath>
#include <Vector3.hpp>

namespace godot {

struct DVector3 {

	union {
		struct {
			double x;
			double y;
			double z;
		};

		double coord[3]; // Not for direct access, use [] operator instead
	};

	inline DVector3(double x, double y, double z) {
		this->x = x;
		this->y = y;
		this->z = z;
	}

	inline DVector3(const Vector3&t):
		x(t.x), y(t.y), z(t.z)
	{}

	inline DVector3() {
		this->x = 0;
		this->y = 0;
		this->z = 0;
	}

	inline const double &operator[](int p_axis) const {
		return coord[p_axis];
	}

	inline double &operator[](int p_axis) {
		return coord[p_axis];
	}

	inline DVector3 &operator+=(const DVector3 &p_v) {
		x += p_v.x;
		y += p_v.y;
		z += p_v.z;
		return *this;
	}

	inline DVector3 operator+(const DVector3 &p_v) const {
		DVector3 v = *this;
		v += p_v;
		return v;
	}

	inline DVector3 &operator-=(const DVector3 &p_v) {
		x -= p_v.x;
		y -= p_v.y;
		z -= p_v.z;
		return *this;
	}

	inline DVector3 operator-(const DVector3 &p_v) const {
		DVector3 v = *this;
		v -= p_v;
		return v;
	}

	inline DVector3 &operator*=(const DVector3 &p_v) {
		x *= p_v.x;
		y *= p_v.y;
		z *= p_v.z;
		return *this;
	}

	inline DVector3 operator*(const DVector3 &p_v) const {
		DVector3 v = *this;
		v *= p_v;
		return v;
	}

	inline DVector3 &operator/=(const DVector3 &p_v) {
		x /= p_v.x;
		y /= p_v.y;
		z /= p_v.z;
		return *this;
	}

	inline DVector3 operator/(const DVector3 &p_v) const {
		DVector3 v = *this;
		v /= p_v;
		return v;
	}

	inline DVector3 &operator*=(double p_scalar) {
		*this *= DVector3(p_scalar, p_scalar, p_scalar);
		return *this;
	}

	inline DVector3 operator*(double p_scalar) const {
		DVector3 v = *this;
		v *= p_scalar;
		return v;
	}

	inline DVector3 &operator/=(double p_scalar) {
		*this /= DVector3(p_scalar, p_scalar, p_scalar);
		return *this;
	}

	inline DVector3 operator/(double p_scalar) const {
		DVector3 v = *this;
		v /= p_scalar;
		return v;
	}

	inline DVector3 operator-() const {
		return DVector3(-x, -y, -z);
	}

	inline bool operator==(const DVector3 &p_v) const {
		return (x == p_v.x && y == p_v.y && z == p_v.z);
	}

	inline bool operator!=(const DVector3 &p_v) const {
		return (x != p_v.x || y != p_v.y || z != p_v.z);
	}

	inline DVector3 abs() const {
		return DVector3(::fabs(x), ::fabs(y), ::fabs(z));
	}

	inline DVector3 ceil() const {
		return DVector3(::ceil(x), ::ceil(y), ::ceil(z));
	}

	inline DVector3 cross(const DVector3 &b) const {
		DVector3 ret(
				(y * b.z) - (z * b.y),
				(z * b.x) - (x * b.z),
				(x * b.y) - (y * b.x));

		return ret;
	}

	inline DVector3 linear_interpolate(const DVector3 &p_b, double p_t) const {
		return DVector3(
				x + (p_t * (p_b.x - x)),
				y + (p_t * (p_b.y - y)),
				z + (p_t * (p_b.z - z)));
	}

	DVector3 bounce(const DVector3 &p_normal) const {
		return -reflect(p_normal);
	}

	inline double length() const {
		double x2 = x * x;
		double y2 = y * y;
		double z2 = z * z;

		return ::sqrt(x2 + y2 + z2);
	}

	inline double length_squared() const {
		double x2 = x * x;
		double y2 = y * y;
		double z2 = z * z;

		return x2 + y2 + z2;
	}

	inline double distance_squared_to(const DVector3 &b) const {
		return (b - *this).length_squared();
	}

	inline double distance_to(const DVector3 &b) const {
		return (b - *this).length();
	}

	inline double dot(const DVector3 &b) const {
		return x * b.x + y * b.y + z * b.z;
	}

	inline double angle_to(const DVector3 &b) const {
		return std::atan2(cross(b).length(), dot(b));
	}

	inline DVector3 direction_to(const DVector3 &p_b) const {
		DVector3 ret(p_b.x - x, p_b.y - y, p_b.z - z);
		ret.normalize();
		return ret;
	}

	inline DVector3 floor() const {
		return DVector3(::floor(x), ::floor(y), ::floor(z));
	}

	inline DVector3 inverse() const {
		return DVector3(1.f / x, 1.f / y, 1.f / z);
	}

	inline bool is_normalized() const {
		return std::abs(length_squared() - 1.f) < 0.00001f;
	}

	inline void normalize() {
		double l = length();
		if (l == 0) {
			x = y = z = 0;
		} else {
			x /= l;
			y /= l;
			z /= l;
		}
	}

	inline DVector3 normalized() const {
		DVector3 v = *this;
		v.normalize();
		return v;
	}

	inline DVector3 reflect(const DVector3 &p_normal) const {
		return -(*this - p_normal * this->dot(p_normal) * 2.0);
	}

	inline void y_rotate(double p_phi) {
		double x0=x, z0=z;
		x=x0*::cos(p_phi) - z0*::sin(p_phi);
		z=x0*::sin(p_phi) + z0*::cos(p_phi);
	}

	inline DVector3 slide(const DVector3 &by) const {
		return by - *this * this->dot(by);
	}
};

} // namespace godot

#endif // DVECTOR3_H
