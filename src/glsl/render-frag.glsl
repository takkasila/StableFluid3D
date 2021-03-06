uniform vec3 u_cam_pos;
uniform vec3 u_cam_up;
uniform vec3 u_cam_lookAt;
uniform float u_cam_vfov;
uniform float u_cam_near;
uniform float u_cam_far;

uniform sampler2D u_texture;
uniform float u_screen_width;
uniform float u_screen_height;

uniform int u_cell_x;
uniform int u_cell_y;
uniform int u_cell_z;

uniform vec3 topColor;
uniform vec3 btmColor;

varying vec2 f_uv;

#define EPSILON 0.0001
#define SCENEBB_POS vec3(float(u_cell_x)/2.0, -1.0, float(u_cell_z)/2.0)
#define SCENEBB_SIZE vec3(float(u_cell_x)/2.0, 1.0, float(u_cell_z)/2.0)
#define SMOKEBB_START vec3(0.0)
#define SMOKEBB_STOP vec3(float(u_cell_x), float(u_cell_y), float(u_cell_z))
#define MAXCELL ivec3(256)
#define SKYBOX_RADIUS 10000.0

#define SUN_DIR  normalize(vec3(float(-u_cell_x)*3.0/5.0, float(-u_cell_y*2), float(-u_cell_z)*3.0/4.0))

struct Ray {
    vec3 start;
    vec3 dir;
    float depth;
};

float checkerboardTexture(vec3 p)
{
    p = floor(mod(p/4.0, 2.0));
    return mod(p.x+p.y+p.z, 2.0);
}

// Input cell index
float smokeDense(ivec3 p)
{
    vec2 tmp = vec2(float(p.x)/float(u_cell_x)
                    , float(p.z)/float(u_cell_z * u_cell_y) + (float(p.y))/float(u_cell_y));
    return texture2D(u_texture, tmp).r;
}

vec3 absorb(vec3 originColor, float amount)
{
    float fogAmount = 1.0 - exp(-amount * 0.5);
    vec3 fogColor = vec3(0.4, 0.4, 0.4);
    return mix(originColor, fogColor, fogAmount);
}

vec3 If(bvec3 cond, vec3 resT, vec3 resF)
{
    vec3 res;
    res.x = cond.x ? resT.x : resF.x;
    res.y = cond.y ? resT.y : resF.y;
    res.z = cond.z ? resT.z : resF.z;    

    return res;
}

float intersectRayCube(vec3 rp, vec3 rd, vec3 cp, vec3 cth, out vec2 t)
{	
	rp -= cp;
	
	vec3 m = 1.0 / -rd;
	vec3 o = If(lessThan(rd, vec3(0.0)), -cth, cth);
	
	vec3 uf = (rp + o) * m;
	vec3 ub = (rp - o) * m;
	
	t.x = max(uf.x, max(uf.y, uf.z));
	t.y = min(ub.x, min(ub.y, ub.z));
	
	// if(ray start == inside cube) 
	if(t.x < 0.0 && t.y > 0.0) {t.xy = t.yx;  return 1.0;}
	
	return t.y < t.x ? 0.0 : (t.x > 0.0 ? 1.0 : -1.0);
}

float intersectRayCubeNorm(vec3 rp, vec3 rd, vec3 cp, vec3 cth, out vec2 t, out vec3 n0, out vec3 n1)
{	
	rp -= cp;
	
	vec3 m = 1.0 / -rd;
    vec3 os = If(lessThan(rd, vec3(0.0)), vec3(1.0), vec3(-1.0));
    //vec3 os = sign(-rd);
	vec3 o = -cth * os;
	
    
	vec3 uf = (rp + o) * m;
	vec3 ub = (rp - o) * m;
	
	//t.x = max(uf.x, max(uf.y, uf.z));
	//t.y = min(ub.x, min(ub.y, ub.z));
	
    if(uf.x > uf.y) {t.x = uf.x; n0 = vec3(os.x, 0.0, 0.0);} else 
                    {t.x = uf.y; n0 = vec3(0.0, os.y, 0.0);}
    if(uf.z > t.x ) {t.x = uf.z; n0 = vec3(0.0, 0.0, os.z);}
    
    if(ub.x < ub.y) {t.y = ub.x; n1 = vec3(os.x, 0.0, 0.0);} else 
                    {t.y = ub.y; n1 = vec3(0.0, os.y, 0.0);}
    if(ub.z < t.y ) {t.y = ub.z; n1 = vec3(0.0, 0.0, os.z);}
    
    
	// if(ray start == inside cube) 
	if(t.x < 0.0 && t.y > 0.0) 
    {
        t.xy = t.yx;  
        
        vec3 n00 = n0;
        n0 = n1;
        n1 = n00;
        
        return 1.0;
    }
	
	return t.y < t.x ? 0.0 : (t.x > 0.0 ? 1.0 : -1.0);
}

bool intersectSphere(vec3 rp, vec3 rd, vec3 cp, float radius, out float outT)
{
    vec3 centerToPoint = rp - cp;
	float a = dot(rd, rd);
	float b = 2.0 * dot(rd, centerToPoint);
	float c = dot(centerToPoint, centerToPoint) - (radius*radius);

	// Solve quadratic equation
	float det = b*b - 4.0 * a*c;
	if (det < 0.0)
		return false;

	float root1 = (-b + sqrt(det)) / (2.0 * a);
	float root2 = (-b - sqrt(det)) / (2.0 * a);

	// Check result
	if (root1 > 0.0 && root2 > 0.0)
		outT = min(root1, root2);
	else
		outT = max(root1, root2);

	if (outT < 0.0)
		return false;

	return true;
}

vec3 rayDirection()
{
    // Creat camera plane
    vec2 uv = f_uv * 2.0 - 1.0;
    vec3 view_n = normalize(u_cam_pos - u_cam_lookAt);
    vec3 view_u = normalize(cross(u_cam_up, view_n));
    vec3 view_v = normalize(cross(view_n, view_u));

    vec3 plane_top = view_v * u_cam_near * tan(radians(u_cam_vfov)/2.0);
    vec3 plane_right = view_u * (u_screen_width/u_screen_height) * length(plane_top);
    return normalize(-view_n * u_cam_near + plane_right * uv.x + plane_top * uv.y);
}

// Volxel traversal along 3D line
float densityTrace(Ray ray)
{
    float totalDense = 0.0;
    vec3 cellSize = (SMOKEBB_STOP - SMOKEBB_START) / float(ivec3(u_cell_x, u_cell_y, u_cell_z));
    vec2 tt;
    vec3 n0, n1;
    int x, y, z, dx, dy, dz;
    if(intersectRayCubeNorm(ray.start, ray.dir, (SMOKEBB_START + SMOKEBB_STOP)/2.0, (SMOKEBB_STOP - SMOKEBB_START)/2.0, tt, n0, n1) > 0.0)
    {
        // Enter cube to reduce surface error
        vec3 startPos, endPos;
        if(tt.x < tt.y)
        {
            startPos = ray.start + ray.dir * tt.x - n0 * EPSILON;
            endPos = ray.start + ray.dir * tt.y + n1 * EPSILON;
        }
        else
        {
            startPos = ray.start;
            endPos = ray.start + ray.dir * tt.x + n0 * EPSILON;
        }
        // endPos -= startPos;
        x = int(floor(startPos.x));
        y = int(floor(startPos.y));
        z = int(floor(startPos.z));
        dx = int(floor(endPos.x));
        dy = int(floor(endPos.y));
        dz = int(floor(endPos.z));
        dx-=x;
        dy-=y;
        dz-=z;
    }
    else
        return 0.0;
        
    int sx, sy, sz, exy, exz, ezy, ax, ay, az, bx, by, bz;
    sx = int(sign(float(dx)));
    sy = int(sign(float(dy)));
    sz = int(sign(float(dz)));
    ax = int(abs(float(dx)));
    ay = int(abs(float(dy)));
    az = int(abs(float(dz)));
    bx = 2*ax;	   by = 2*ay;	  bz = 2*az;
    exy = ay-ax;   exz = az-ax;	  ezy = ay-az;

    vec3 cellPos;
    for(int n = 0; n < MAXCELL.x + MAXCELL.y + MAXCELL.z; n++)
    {
        if(n >= ax+ay+az+1)
            break;

        // cellPos = vec3(x,y,z)*cellSize + cellSize/2.0;
        intersectRayCubeNorm(ray.start, ray.dir, cellPos, cellSize/2.0, tt, n0, n1);
        if(tt.x < tt.y)
        {
            // cellPos = ray.start + ray.dir * tt.x - n0 * EPSILON;
            // totalDense += smokeDense(cellPos) * (tt.y-tt.x);
            totalDense += smokeDense(ivec3(x,y,z)) * (tt.y-tt.x);
        }
        else
        {
            cellPos = ray.start + ray.dir * tt.x + n0 * EPSILON;
            // totalDense += smokeDense(cellPos) * length(cellPos - ray.start);
            totalDense += smokeDense(ivec3(x,y,z)) * length(cellPos - ray.start);
        }
        
        // Update
        if ( exy < 0 ) {
            if ( exz < 0 ) {
            x += sx;
            exy += by; exz += bz;
            }
            else  {
            z += sz;
            exz -= bx; ezy += by;
            }
        }
        else {
            if ( ezy < 0 ) {
            z += sz;
            exz -= bx; ezy += by;
            }
            else  {
            y += sy;
            exy -= bx; ezy -= bz;
            }
        }
    }
    return totalDense;
}

vec3 renderScene(Ray ray)
{
    vec2 tt;
    vec3 n0, n1;
    vec3 color = vec3(0.0);

    intersectRayCubeNorm(ray.start, ray.dir, SCENEBB_POS, SCENEBB_SIZE, tt, n0, n1);
    if(tt.x < tt.y)
    {
        //Outside plane 
        vec3 tmpPos = ray.start + ray.dir * tt.x - n0 * EPSILON;
        color = vec3(checkerboardTexture(tmpPos));
        
        if(intersectRayCube(tmpPos, -SUN_DIR, (SMOKEBB_START + SMOKEBB_STOP)/2.0, (SMOKEBB_STOP-SMOKEBB_START)/2.0, tt) > 0.0)
        {
            //Hit smokebox, will need to trace smoke for density
            Ray shadowRay;
            shadowRay.start = tmpPos;
            shadowRay.dir = -SUN_DIR;
            color *= 1.0 - densityTrace(shadowRay);
        }
    }
    else
    {
        //Inside plane
        color = vec3(checkerboardTexture(ray.start + ray.dir * tt.x + n0 * EPSILON));
    }
    return color;
}

vec3 renderSkyBox(Ray ray)
{
    // return vec3(0.75);
    float outT;
    if(intersectSphere(ray.start, ray.dir, vec3(0.0), SKYBOX_RADIUS, outT))
    {
        float tempY = (ray.start.y + ray.dir.y * outT)/SKYBOX_RADIUS;
        tempY = (tempY+1.0)/2.0;
        return mix(btmColor, topColor, tempY);
    }
}

vec3 render(Ray ray)
{
    vec2 sceneDist;
    vec2 smokeDist;

    if (intersectRayCube(ray.start, ray.dir, SCENEBB_POS, SCENEBB_SIZE, sceneDist) > 0.0)
    {
        vec3 sceneColor = renderScene(ray);
        if(intersectRayCube(ray.start, ray.dir, (SMOKEBB_START + SMOKEBB_STOP)/2.0, (SMOKEBB_STOP-SMOKEBB_START)/2.0, smokeDist) > 0.0)
        {
            // Hit both
            if(sceneDist.x <= smokeDist.x)
            {
                return sceneColor;
            }
            else
            {
                float totalDense = densityTrace(ray);
                return absorb(sceneColor, totalDense);
            }
        }
        else
        {
            // Hit only scene
            return sceneColor;
        }
    }
    else
    {
        vec3 skyboxColor = renderSkyBox(ray);
        if(intersectRayCube(ray.start, ray.dir, (SMOKEBB_START + SMOKEBB_STOP)/2.0, (SMOKEBB_STOP-SMOKEBB_START)/2.0, smokeDist) > 0.0)
        {
            // Hit smoke
            float totalDense = densityTrace(ray);
            return absorb(skyboxColor, totalDense);
        }
        else
        {
            // Hit only skybox
            return skyboxColor;
        }
    }
}

void main() {
    Ray ray;
    ray.start = u_cam_pos;
    ray.dir = rayDirection();
    ray.depth = 0.0;

    gl_FragColor = vec4(render(ray), 1.0);
}